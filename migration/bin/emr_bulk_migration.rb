#!/usr/bin/env ruby

require 'rest-client'
require 'yaml'
require 'json'
require 'mysql2'
require 'logger'
require 'set'
require 'fileutils'
require 'optparse'
require 'csv'

# ============================================================================
# OPENMRS BULK MIGRATION TO PROXY
# ============================================================================
# Extrai pacientes activos (voided=0) do OpenMRS e envia para o Proxy.
# Proxy atribui NPIDs automaticamente no endpoint /v1/add_person.
#
# Uso:
#   ruby bin/emr_bulk_migration.rb
#   ruby bin/emr_bulk_migration.rb --dry-run
#   ruby bin/emr_bulk_migration.rb --start-from 5000
# ============================================================================

DDE_ROOT    = File.expand_path('../..',      __dir__)
LOGS_DIR    = File.expand_path('../logs',    __dir__)
DATA_DIR    = File.expand_path('../data',    __dir__)
REPORTS_DIR = File.expand_path('../reports', __dir__)

FileUtils.mkdir_p(LOGS_DIR)
FileUtils.mkdir_p(DATA_DIR)
FileUtils.mkdir_p(REPORTS_DIR)

# logs/ — podem ser apagados
LOG_FILE       = "#{LOGS_DIR}/openmrs_migration_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log"
FAILED_FILE    = "#{LOGS_DIR}/failed_records.jsonl"
DISCARDED_FILE = "#{LOGS_DIR}/discarded_records.jsonl"

# data/ — NÃO APAGAR (controlo de progresso e mapeamento)
PROGRESS_FILE  = "#{DATA_DIR}/migration_progress.txt"
MAPPING_FILE   = "#{DATA_DIR}/migration_mapping.csv"

class Logger
  class MultiIO
    def initialize(*targets)
      @targets = targets
    end

    def write(msg)
      @targets.each { |t| t.write(msg) }
    end

    def close
      @targets.each(&:close)
    end
  end
end

logger_device = Logger::MultiIO.new(STDOUT, File.open(LOG_FILE, 'a'))
LOGGER = Logger.new(logger_device)
LOGGER.level = Logger::DEBUG
LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
end

# Configuration
MIGRATION_CONFIG_FILE = "#{DDE_ROOT}/config/emr_migration.yml"
VOIDED = 0
TOKEN_EXPIRY_BUFFER = 300

# ============================================================================
# CLI OPTIONS
# ============================================================================
cli_options = { dry_run: false, start_from: nil, limit: nil }

OptionParser.new do |opts|
  opts.banner = "Usage: ruby emr_bulk_migration.rb [options]"
  opts.on("--dry-run", "Simula sem enviar dados ao Proxy") { cli_options[:dry_run] = true }
  opts.on("--start-from ID", Integer, "Retoma a partir de um person_id específico") do |id|
    cli_options[:start_from] = id
  end
  opts.on("--limit N", Integer, "Para após migrar N pacientes (útil para testes)") do |n|
    cli_options[:limit] = n
  end
  opts.on("-h", "--help") { puts opts; exit }
end.parse!

DRY_RUN    = cli_options[:dry_run]
START_FROM = cli_options[:start_from]
MAX_PATIENTS = cli_options[:limit]

# ============================================================================
# MIGRATION CLASS
# ============================================================================
class OpenMRSMigration
  REQUIRED_FIELDS = %w[
    given_name
    family_name
    birthdate
    birthdate_estimated
    home_district
    home_village
    home_traditional_authority
  ].freeze

  class NoNpidsAvailable < StandardError; end

  def initialize
    @proxy_config     = load_proxy_config
    @mysql_config     = load_mysql_config
    @migration_config = load_migration_settings

    @batch_size        = @migration_config['batch_size']        || 100
    @max_retries       = @migration_config['max_retries']       || 3
    @retry_delay       = @migration_config['retry_delay']       || 2
    @http_open_timeout = @migration_config['http_open_timeout'] || 10
    @http_read_timeout = @migration_config['http_read_timeout'] || 30

    @token            = nil
    @token_expires_at = nil

    @success_count     = 0
    @failed_records    = []
    @discarded_records = []
    @migrated_ids      = load_progress
    init_mapping_file
  end

  # ========================================================================
  # PROGRESS FILE
  # ========================================================================

  def load_progress
    return Set.new unless File.exist?(PROGRESS_FILE)

    ids = File.readlines(PROGRESS_FILE, chomp: true).map(&:to_i).to_set
    LOGGER.info "↩ Retomando: #{ids.size} paciente(s) já migrados anteriormente serão ignorados."
    ids
  end

  def save_progress(person_id)
    File.open(PROGRESS_FILE, 'a') do |f|
      f.flock(File::LOCK_EX)
      f.puts(person_id)
      f.flock(File::LOCK_UN)
    end
    @migrated_ids << person_id
  end

  def init_mapping_file
    return if File.exist?(MAPPING_FILE)

    File.open(MAPPING_FILE, 'w') { |f| f.puts('person_id,npid,doc_id') }
  end

  def save_mapping(person_id, npid, doc_id)
    File.open(MAPPING_FILE, 'a') do |f|
      f.flock(File::LOCK_EX)
      f.puts("#{person_id},#{npid},#{doc_id}")
      f.flock(File::LOCK_UN)
    end
  end

  # ========================================================================
  # CONFIGURATION
  # ========================================================================

  def load_config_file
    raise "Ficheiro de configuração não encontrado: #{MIGRATION_CONFIG_FILE}" unless File.exist?(MIGRATION_CONFIG_FILE)

    YAML.load(File.read(MIGRATION_CONFIG_FILE), aliases: true)
  end

  def load_proxy_config
    config = load_config_file
    raise "Secção 'proxy' em falta em #{MIGRATION_CONFIG_FILE}" unless config['proxy']

    {
      protocol: config['proxy']['protocol'],
      host:     config['proxy']['host'],
      port:     config['proxy']['port'],
      username: config['proxy']['username'],
      password: config['proxy']['password']
    }
  end

  def load_mysql_config
    config = load_config_file
    raise "Secção 'openmrs' em falta em #{MIGRATION_CONFIG_FILE}" unless config['emr_database']

    config['emr_database']
  end

  def load_migration_settings
    config = load_config_file
    config['migration'] || {}
  end

  # ========================================================================
  # AUTHENTICATION
  # ========================================================================

  def token_valid?
    @token && @token_expires_at && Time.now < @token_expires_at
  end

  def authenticate_proxy
    url = "#{@proxy_config[:protocol]}://#{@proxy_config[:host]}:#{@proxy_config[:port]}/v1/login"

    payload = {
      username: @proxy_config[:username],
      password: @proxy_config[:password]
    }

    LOGGER.info "Autenticando no Proxy (#{@proxy_config[:host]}:#{@proxy_config[:port]})..."

    begin
      response = RestClient::Request.execute(
        method:       :post,
        url:          url,
        payload:      payload.to_json,
        headers:      { content_type: :json },
        open_timeout: @http_open_timeout,
        read_timeout: @http_read_timeout
      )

      data = JSON.parse(response)
      @token = data['access_token']

      expires_in        = data['expires_in']&.to_i || 3600
      @token_expires_at = Time.now + expires_in - TOKEN_EXPIRY_BUFFER

      LOGGER.info "✓ Autenticação bem-sucedida (token válido por ~#{expires_in / 60}min)"
      @token

    rescue RestClient::ExceptionWithResponse => e
      LOGGER.error "✗ Erro na autenticação: #{e.response}"
      raise "Falha ao autenticar no Proxy"
    rescue Errno::ECONNREFUSED => e
      LOGGER.error "✗ Proxy inacessível: #{e.message}"
      raise "Não foi possível conectar ao Proxy em #{@proxy_config[:host]}:#{@proxy_config[:port]}"
    end
  end

  def ensure_valid_token
    return if token_valid?

    LOGGER.info "Token expirado ou ausente — re-autenticando..."
    authenticate_proxy
  end

  # ========================================================================
  # MYSQL — leitura paginada
  # ========================================================================

  def mysql_connection
    Mysql2::Client.new(
      host:      @mysql_config['host'],
      port:      @mysql_config['port'],
      username:  @mysql_config['username'],
      password:  @mysql_config['password'],
      database:  @mysql_config['database'],
      reconnect: true
    )
  end

  def count_active_patients(conn, min_id)
    row = conn.query(
      "SELECT COUNT(DISTINCT p.person_id) AS total
       FROM patient pt
       INNER JOIN person p ON pt.patient_id = p.person_id AND p.voided = #{VOIDED}
       WHERE pt.voided = 0 AND p.person_id > #{min_id}"
    ).first
    row['total'].to_i
  end

  def fetch_patients_page(conn, last_id, limit)
    # Mapeamento de endereços (Moçambique):
    #   county_district → home_district              (Distrito)
    #   address2        → home_traditional_authority  (Posto Administrativo)
    #   address6        → home_village                (Localidade)
    #   state_province  → current_district            (Província)
    #
    # Usa subqueries para garantir exactamente 1 endereço e 1 nome por paciente
    # (o mais antigo não-voided por min ID), evitando duplicação de registos.
    query = <<~SQL
      SELECT
        p.person_id,
        p.gender,
        p.birthdate,
        p.birthdate_estimated,
        pn.given_name,
        pn.middle_name,
        pn.family_name,
        COALESCE(pad3.county_district, 'Desconhecido') AS home_district,
        COALESCE(pad3.address2, 'Desconhecido')        AS home_traditional_authority,
        COALESCE(pad3.address6, 'Desconhecido')        AS home_village,
        pad3.state_province   AS current_district,
        pad3.address2         AS current_traditional_authority,
        pad3.address1         AS current_village
      FROM patient pt
      INNER JOIN person p ON p.person_id = pt.patient_id AND p.voided = #{VOIDED}
      LEFT JOIN (
        SELECT pad1.*
        FROM person_address pad1
        INNER JOIN (
          SELECT person_id, MIN(person_address_id) AS id
          FROM person_address
          WHERE voided = 0
          GROUP BY person_id
        ) pad2 ON pad1.person_id = pad2.person_id AND pad1.person_address_id = pad2.id
      ) pad3 ON pad3.person_id = pt.patient_id
      LEFT JOIN (
        SELECT pn1.*
        FROM person_name pn1
        INNER JOIN (
          SELECT person_id, MIN(person_name_id) AS id
          FROM person_name
          WHERE voided = 0
          GROUP BY person_id
        ) pn2 ON pn1.person_id = pn2.person_id AND pn1.person_name_id = pn2.id
      ) pn ON pn.person_id = pt.patient_id
      WHERE pt.voided = 0
        AND p.person_id > #{last_id}
      ORDER BY p.person_id
      LIMIT #{limit}
    SQL

    conn.query(query, as: :hash).to_a
  end

  # ========================================================================
  # VALIDATION
  # ========================================================================

  def validate_patient(patient)
    REQUIRED_FIELDS.select do |field|
      patient[field].nil? || patient[field].to_s.strip.empty?
    end
  end

  def discard_patient(patient, missing_fields)
    record = {
      person_id:      patient['person_id'],
      missing_fields: missing_fields,
      discarded_at:   Time.now.iso8601
    }
    @discarded_records << record

    File.open(DISCARDED_FILE, 'a') do |f|
      f.flock(File::LOCK_EX)
      f.puts(record.to_json)
      f.flock(File::LOCK_UN)
    end

    LOGGER.warn "⚠ Descartado person_id=#{patient['person_id']} | Campos em falta: #{missing_fields.join(', ')}"
  end

  # ========================================================================
  # PAYLOAD FORMAT
  # ========================================================================

  def format_patient_payload(patient)
    {
      given_name:           patient['given_name'].to_s.strip,
      middle_name:          patient['middle_name'].to_s.strip,
      family_name:          patient['family_name'].to_s.strip,
      gender:               patient['gender']&.upcase || '',
      birthdate:            patient['birthdate']&.to_s || '',
      birthdate_estimated:  (patient['birthdate_estimated'].to_i == 1).to_s,
      attributes: {
        current_district:              patient['current_district'].to_s.strip,
        current_village:               patient['current_village'].to_s.strip,
        current_traditional_authority: patient['current_traditional_authority'].to_s.strip,
        home_district:                 patient['home_district'].to_s.strip,
        home_village:                  patient['home_village'].to_s.strip,
        home_traditional_authority:    patient['home_traditional_authority'].to_s.strip,
        occupation:                    patient['occupation'].to_s.strip
      }
    }
  end

  # ========================================================================
  # PUSH TO PROXY
  # ========================================================================

  def push_patient(patient, index, total)
    ensure_valid_token

    url     = "#{@proxy_config[:protocol]}://#{@proxy_config[:host]}:#{@proxy_config[:port]}/v1/add_person"
    payload = format_patient_payload(patient)

    if DRY_RUN
      LOGGER.info "[DRY-RUN] [#{index}/#{total}] person_id=#{patient['person_id']}"
      @success_count += 1
      return
    end

    retry_count = 0

    begin
      response = RestClient::Request.execute(
        method:       :post,
        url:          url,
        payload:      payload.to_json,
        headers:      { Authorization: "Bearer #{@token}", content_type: :json },
        open_timeout: @http_open_timeout,
        read_timeout: @http_read_timeout
      )

      if [200, 201].include?(response.code)
        data   = JSON.parse(response.body)
        npid   = data['npid']
        doc_id = data['doc_id']
        @success_count += 1
        save_progress(patient['person_id'])
        save_mapping(patient['person_id'], npid, doc_id)
        LOGGER.info "✓ [#{index}/#{total}] person_id=#{patient['person_id']} (NPID: #{npid})"
      else
        record_failure(patient, payload, "HTTP #{response.code}: #{response.body}")
        LOGGER.warn "✗ [#{index}/#{total}] person_id=#{patient['person_id']} | HTTP inesperado: #{response.code}"
      end

    rescue RestClient::Unauthorized
      if retry_count.zero?
        LOGGER.warn "⚠ [#{index}/#{total}] 401 Unauthorized — renovando token..."
        authenticate_proxy
        retry_count += 1
        retry
      else
        record_failure(patient, payload, "401 após renovação de token")
        LOGGER.error "✗ [#{index}/#{total}] Falha de autenticação persistente"
      end

    rescue RestClient::UnprocessableEntity => e
      body = e.response.to_s rescue ''
      if body.include?('No NPIDs to assign')
        raise NoNpidsAvailable, "Proxy sem NPIDs disponíveis. Reabasteça o stock e retome com: ruby #{$0}"
      else
        record_failure(patient, payload, "HTTP 422: #{body}")
        LOGGER.error "✗ [#{index}/#{total}] Entidade inválida (422): #{body}"
      end

    rescue RestClient::ServiceUnavailable,
           RestClient::BadGateway,
           Timeout::Error,
           Errno::ECONNRESET,
           Errno::ECONNREFUSED => e
      retry_count += 1
      if retry_count <= @max_retries
        wait_time = @retry_delay**retry_count
        LOGGER.warn "⏱ [#{index}/#{total}] Tentativa #{retry_count}/#{@max_retries} — aguardando #{wait_time}s... (#{e.class})"
        sleep(wait_time)
        retry
      else
        record_failure(patient, payload, "Retry esgotado (#{@max_retries}x): #{e.message}")
        LOGGER.error "✗ [#{index}/#{total}] Falha após #{@max_retries} tentativas"
      end

    rescue RestClient::ExceptionWithResponse => e
      record_failure(patient, payload, "HTTP #{e.http_code}: #{e.response}")
      LOGGER.error "✗ [#{index}/#{total}] Erro HTTP #{e.http_code}"

    rescue StandardError => e
      record_failure(patient, payload, e.message)
      LOGGER.error "✗ [#{index}/#{total}] Erro: #{e.message}"
    end
  end

  def record_failure(patient, _payload, error)
    record = {
      person_id: patient['person_id'],
      error:     error.to_s,
      failed_at: Time.now.iso8601
    }
    @failed_records << record

    File.open(FAILED_FILE, 'a') do |f|
      f.flock(File::LOCK_EX)
      f.puts(record.to_json)
      f.flock(File::LOCK_UN)
    end
  end

  # ========================================================================
  # PROCESS IN BATCHES
  # ========================================================================

  def process_in_batches
    ensure_valid_token

    conn   = mysql_connection
    min_id = START_FROM ? (START_FROM - 1) : 0

    LOGGER.info "▶ Iniciando a partir de person_id > #{min_id}" if START_FROM

    total_in_db   = count_active_patients(conn, min_id)
    LOGGER.info "Total de pacientes activos no DB (elegíveis): #{total_in_db}"

    last_id         = min_id
    global_index    = 0
    batch_number    = 0
    skipped_count   = 0
    discarded_count = 0

    loop do
      page = fetch_patients_page(conn, last_id, @batch_size)
      break if page.empty?

      batch_number += 1
      to_send = []

      page.each do |patient|
        last_id = patient['person_id']

        if @migrated_ids.include?(patient['person_id'])
          skipped_count += 1
          next
        end

        missing = validate_patient(patient)
        if missing.any?
          discard_patient(patient, missing)
          discarded_count += 1
          next
        end

        to_send << patient
      end

      unless to_send.empty?
        LOGGER.info "\n--- Batch #{batch_number} | #{to_send.size} paciente(s) a enviar ---"
        to_send.each do |patient|
          global_index += 1
          push_patient(patient, global_index, total_in_db)
          sleep(0.1) if (global_index % 10).zero?

          if MAX_PATIENTS && @success_count >= MAX_PATIENTS
            LOGGER.info "✋ Limite de #{MAX_PATIENTS} paciente(s) atingido — a parar."
            return
          end
        end
      end
    end

    LOGGER.info "⏭ #{skipped_count} paciente(s) ignorados (já migrados)."        if skipped_count > 0
    LOGGER.info "⚠ #{discarded_count} paciente(s) descartados. Ver: #{DISCARDED_FILE}" if discarded_count > 0
    LOGGER.info "\n" + "=" * 60
    LOGGER.info "MIGRAÇÃO CONCLUÍDA"
    LOGGER.info "=" * 60
  rescue NoNpidsAvailable => e
    LOGGER.error "\n" + "!" * 60
    LOGGER.error "PARAGEM DE EMERGÊNCIA: #{e.message}"
    LOGGER.error "Migrados até agora: #{@success_count} paciente(s)"
    LOGGER.error "O progresso foi guardado. Retome com: ruby #{$0}"
    LOGGER.error "!" * 60
    raise
  ensure
    conn&.close
  end

  # ========================================================================
  # RELATÓRIO DE NÃO-MIGRADOS (CSV para seguimento)
  # ========================================================================

  def generate_followup_report
    rows = []

    if File.exist?(DISCARDED_FILE)
      File.readlines(DISCARDED_FILE, chomp: true).each do |line|
        record = JSON.parse(line)
        rows << [
          record['person_id'],
          'descartado',
          record['missing_fields']&.join(', '),
          record['discarded_at']
        ]
      end
    end

    if File.exist?(FAILED_FILE)
      File.readlines(FAILED_FILE, chomp: true).each do |line|
        record = JSON.parse(line)
        rows << [
          record['person_id'],
          'falhou',
          record['error'],
          record['failed_at']
        ]
      end
    end

    return if rows.empty?

    timestamp   = Time.now.strftime('%Y%m%d_%H%M%S')
    report_file = "#{REPORTS_DIR}/nao_migrados_#{timestamp}.csv"

    CSV.open(report_file, 'w', write_headers: true,
             headers: %w[person_id estado detalhe data]) do |csv|
      rows.each { |r| csv << r }
    end

    LOGGER.info "📋 Relatório gerado: #{report_file} (#{rows.size} registos)"
    report_file
  end

  # ========================================================================
  # SUMMARY
  # ========================================================================

  def summary
    total = @success_count + @failed_records.count

    LOGGER.info "\n" + "#" * 60
    LOGGER.info "# RESUMO DA MIGRAÇÃO"
    LOGGER.info "#" * 60
    LOGGER.info "Database:             #{@mysql_config['database']}"
    LOGGER.info "Modo:                 #{DRY_RUN ? 'DRY-RUN (nenhum dado enviado)' : 'PRODUÇÃO'}"
    LOGGER.info "Pacientes migrados:   #{@success_count}"
    LOGGER.info "Descartados:          #{@discarded_records.size}"
    LOGGER.info "Erros de envio:       #{@failed_records.size}"
    if total > 0
      LOGGER.info "Taxa de sucesso:      #{(@success_count.to_f / total * 100).round(2)}%"
    end
    LOGGER.info "Log principal:        #{LOG_FILE}"
    LOGGER.info "Mapeamento (NPID):    #{MAPPING_FILE}"
    LOGGER.info "Registos com falha:   #{FAILED_FILE}"  if @failed_records.any?
    LOGGER.info "Registos descartados: #{DISCARDED_FILE}" if @discarded_records.any?

    generate_followup_report

    LOGGER.info "#" * 60
  end
end

# ============================================================================
# ENTRY POINT
# ============================================================================
if __FILE__ == $0
  LOGGER.info "*** MODO DRY-RUN ACTIVO — nenhum dado será enviado ao Proxy ***" if DRY_RUN

  begin
    LOGGER.info "╔" + "=" * 58 + "╗"
    LOGGER.info "║  OpenMRS Bulk Migration to Proxy                      ║"
    LOGGER.info "╚" + "=" * 58 + "╝"

    migration = OpenMRSMigration.new
    migration.process_in_batches
    migration.summary

  rescue OpenMRSMigration::NoNpidsAvailable
    migration&.summary
    exit 2

  rescue StandardError => e
    LOGGER.error "FATAL: #{e.message}"
    LOGGER.error e.backtrace.join("\n")
    exit 1
  end
end

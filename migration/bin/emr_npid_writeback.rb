#!/usr/bin/env ruby


require 'mysql2'
require 'yaml'
require 'csv'
require 'logger'
require 'fileutils'

# ============================================================================
# EMRS NPID WRITE-BACK THIS WILL BE UPDATED WITH REAL PATIENT IDENTIFIERS
# ============================================================================
# Lê o mapeamento gerado pela migração (migration_mapping.csv) e insere
# no OpenMRS dois patient_identifiers por paciente:
#   - NPID    → identifier_type = 3,  preferred = 1
#   - doc_id  → identifier_type = 18, preferred = 0
#
# Uso:
#   ruby bin/openmrs_npid_writeback.rb
#   ruby bin/openmrs_npid_writeback.rb --dry-run
# ============================================================================

DDE_ROOT  = File.expand_path('../..',      __dir__)
LOGS_DIR  = File.expand_path('../logs',    __dir__)
DATA_DIR  = File.expand_path('../data',    __dir__)

FileUtils.mkdir_p(LOGS_DIR)
FileUtils.mkdir_p(DATA_DIR)

# data/ — NÃO APAGAR (controlo de progresso e mapeamento)
MAPPING_FILE   = "#{DATA_DIR}/migration_mapping.csv"
WRITEBACK_DONE = "#{DATA_DIR}/writeback_progress.txt"

# logs/ — podem ser apagados
WRITEBACK_LOG  = "#{LOGS_DIR}/npid_writeback_#{Time.now.strftime('%Y%m%d_%H%M%S')}.log"

CONFIG_FILE    = "#{DDE_ROOT}/config/emr_migration.yml"

NPID_IDENTIFIER_TYPE   =  3    # NPID
DOC_ID_IDENTIFIER_TYPE = 18   # DDE doc_id (UUID do proxy)
LOCATION_ID            = 319
BATCH_SIZE             = 500

# ============================================================================
# LOGGING
# ============================================================================
class Logger
  class MultiIO
    def initialize(*targets) = @targets = targets
    def write(msg) = @targets.each { |t| t.write(msg) }
    def close = @targets.each(&:close)
  end
end

logger_device = Logger::MultiIO.new(STDOUT, File.open(WRITEBACK_LOG, 'a'))
LOGGER = Logger.new(logger_device)
LOGGER.formatter = proc { |sev, dt, _, msg| "[#{dt.strftime('%Y-%m-%d %H:%M:%S')}] #{sev}: #{msg}\n" }

# ============================================================================
# CLI
# ============================================================================
DRY_RUN = ARGV.include?('--dry-run')
LOGGER.info '*** MODO DRY-RUN — nenhum dado será escrito no EMR-Database ***' if DRY_RUN

# ============================================================================
# HELPERS
# ============================================================================
def load_config
  raise "Ficheiro não encontrado: #{CONFIG_FILE}" unless File.exist?(CONFIG_FILE)

  YAML.load(File.read(CONFIG_FILE), aliases: true)
end

def mysql_connection(cfg)
  Mysql2::Client.new(
    host:      cfg['host'],
    port:      cfg['port'].to_i,
    username:  cfg['username'],
    password:  cfg['password'],
    database:  cfg['database'],
    reconnect: true
  )
end

def load_done_ids
  return [] unless File.exist?(WRITEBACK_DONE)

  File.readlines(WRITEBACK_DONE, chomp: true).map(&:to_i)
end

def mark_done(person_id)
  File.open(WRITEBACK_DONE, 'a') { |f| f.puts(person_id) }
end

def identifier_exists?(conn, person_id, identifier_type, identifier)
  conn.query(
    "SELECT COUNT(*) AS c FROM patient_identifier
     WHERE patient_id = #{person_id}
       AND identifier_type = #{identifier_type}
       AND identifier = '#{conn.escape(identifier)}'"
  ).first['c'].to_i > 0
end

# ============================================================================
# MAIN
# ============================================================================
unless File.exist?(MAPPING_FILE)
  LOGGER.error "Ficheiro de mapeamento não encontrado: #{MAPPING_FILE}"
  LOGGER.error 'Execute primeiro o script de migração: ruby bin/emr_bulk_migration.rb'
  exit 1
end

config   = load_config
conn     = mysql_connection(config['emr_database'])
done_ids = load_done_ids.to_set

rows    = CSV.read(MAPPING_FILE, headers: true)
total   = rows.size
pending = rows.reject { |r| done_ids.include?(r['person_id'].to_i) }

LOGGER.info '╔' + '=' * 58 + '╗'
LOGGER.info '║  OpenMRS NPID Write-Back                              ║'
LOGGER.info '╚' + '=' * 58 + '╝'
LOGGER.info "Total no mapeamento : #{total}"
LOGGER.info "Já processados      : #{done_ids.size}"
LOGGER.info "A processar agora   : #{pending.size}"

success_count = 0
skip_count    = 0
error_count   = 0

pending.each_slice(BATCH_SIZE).with_index(1) do |batch, batch_num|
  values = []

  batch.each do |row|
    person_id = row['person_id'].to_i
    npid      = row['npid'].to_s.strip
    doc_id    = row['doc_id'].to_s.strip

    npid_skip   = npid.empty?   || identifier_exists?(conn, person_id, NPID_IDENTIFIER_TYPE,   npid)
    doc_id_skip = doc_id.empty? || identifier_exists?(conn, person_id, DOC_ID_IDENTIFIER_TYPE, doc_id)

    if npid_skip && doc_id_skip
      LOGGER.info "⏭ person_id=#{person_id} | ambos já existem — ignorado"
      mark_done(person_id)
      skip_count += 1
      next
    end

    # NPID → type 3, preferred = 1
    unless npid_skip
      values << "(#{person_id}, '#{conn.escape(npid)}', #{NPID_IDENTIFIER_TYPE}, 1, #{LOCATION_ID}, 1, NOW(), 0, uuid())"
    end

    # doc_id → type 18, preferred = 0
    unless doc_id_skip
      values << "(#{person_id}, '#{conn.escape(doc_id)}', #{DOC_ID_IDENTIFIER_TYPE}, 0, #{LOCATION_ID}, 1, NOW(), 0, uuid())"
    end
  end

  next if values.empty?

  sql = <<~SQL
    INSERT INTO patient_identifier
      (patient_id, identifier, identifier_type, preferred, location_id, creator, date_created, voided, uuid)
    VALUES
      #{values.join(",\n      ")}
  SQL

  if DRY_RUN
    LOGGER.info "[DRY-RUN] Batch #{batch_num} | #{values.size} linha(s) que seriam inseridas"
  else
    begin
      conn.query(sql)
      batch.each do |row|
        person_id = row['person_id'].to_i
        npid      = row['npid'].to_s.strip
        doc_id    = row['doc_id'].to_s.strip
        mark_done(person_id)
        LOGGER.info "✓ person_id=#{person_id} | NPID=#{npid} (type 3) | doc_id=#{doc_id} (type 18)"
        success_count += 1
      end
    rescue Mysql2::Error => e
      LOGGER.error "✗ Batch #{batch_num} falhou: #{e.message}"
      error_count += batch.size
    end
  end
end

LOGGER.info ''
LOGGER.info '#' * 60
LOGGER.info '# RESUMO DO WRITE-BACK'
LOGGER.info '#' * 60
LOGGER.info "Inseridos com sucesso : #{success_count}"
LOGGER.info "Ignorados (duplicados): #{skip_count}"
LOGGER.info "Erros                 : #{error_count}"
LOGGER.info "Log                   : #{WRITEBACK_LOG}"
LOGGER.info '#' * 60

conn.close

# This file should contain all the record creation needed to seed the database with its default values.

# === Person Identifier Types (Mozambique) ===
[
  { code: 'BI',            name: 'Bilhete de Identidade',   description: 'Documento de identificação nacional' },
  { code: 'CERTIDAO_NASC', name: 'Certidão de Nascimento',  description: 'Certidão de nascimento emitida pelo registo civil' },
  { code: 'CARTAO_ELEITOR',name: 'Cartão de Eleitor',       description: 'Cartão de recenseamento eleitoral' },
  { code: 'CARTA_CONDUCAO',name: 'Carta de Condução',       description: 'Licença de condução' },
  { code: 'PASSAPORTE',    name: 'Passaporte',              description: 'Passaporte nacional ou estrangeiro' },
  { code: 'DIRE',          name: 'DIRE',                    description: 'Documento de Identificação de Residentes Estrangeiros' },
  { code: 'NID_ANTIGO',    name: 'NID Antigo',              description: 'Número de Identificação antigo' },
  { code: 'NUIT',          name: 'NUIT',                    description: 'Número Único de Identificação Tributária' },
  { code: 'NUIC',          name: 'NUIC',                    description: 'Número Único de Identificação do Cidadão' },
  { code: 'SEM_DOCUMENTO', name: 'Sem Documento',           description: 'Paciente sem documento de identificação' }
].each do |attrs|
  PersonIdentifierType.find_or_create_by(code: attrs[:code]) do |t|
    t.name        = attrs[:name]
    t.description = attrs[:description]
  end
end


# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

#Update to DDE 4
Config.create!(config: 'push_seq_update',
               config_value: 0,
               description: 'push vector clock updates',
               uuid: 'ba45bb9c-9dca-11eb-a899-dc41a91e235e') unless Config.find_by_config('push_seq_update')

Config.create!(config: 'push_seq_new',
               config_value: 0,
               description: 'push vector clock new records',
               uuid: '6dcfeb1f-d980-11eb-9643-00ffc8ad464b') unless Config.find_by_config('push_seq_new')

Config.create!(config: 'pull_seq_update',
               config_value: 0,
               description: 'pull vector clock updates',
               uuid: 'c22d75c6-9dca-11eb-a899-dc41a91e235e') unless Config.find_by_config('pull_seq_update')

Config.create!(config: 'pull_seq_new',
               config_value: 0,
               description: 'pull vector clock new',
               uuid: '5ba698fe-d980-11eb-9643-00ffc8ad464b') unless Config.find_by_config('pull_seq_new')

Config.create!(config: 'npid_seq',
               config_value: 0,
               description: 'NPID pull vector clock',
               uuid: 'ebc28cab-b7d8-11eb-8cf6-dc41a91e235e') unless Config.find_by_config('npid_seq')

if  ENV['MASTER'] == 'true' 
  DashboardStat.find_or_create_by(name: 'npid_balance',
                                value: {})

  DashboardStat.find_or_create_by(name: 'location_npid_balance',
                                  value: {})

  DashboardStat.find_or_create_by(name: 'dashboard_stats',
                                  value: {})
end               



unless User.exists?
#Load proxy Meta data
metadata_sql_files = %w[dde4_metadata dde4_locations]
connection = ActiveRecord::Base.connection
(metadata_sql_files || []).each do |metadata_sql_file|
  puts "Loading #{metadata_sql_file} metadata sql file"
  sql = File.read("db/meta_data/#{metadata_sql_file}.sql")
    statements = sql.split(/;$/)
    statements.pop

    ActiveRecord::Base.transaction do
      statements.each do |statement|
        connection.execute(statement)
      end
    end
    puts "Loaded #{metadata_sql_file} metadata sql file successfully"
    puts ''
  end
else
  # Set admin as a default user
  User.where(username: "admin").update(default_user: true)
end 

return unless ENV['MASTER'] == 'true' # Do not add contraints if it is not a master

# -----------------------------
# Seed Regions (Provinces)
# -----------------------------
require 'csv'

puts "Seeding Provinces from CSV..."

csv_path = Rails.root.join('db', 'seeds', 'regions_from_2025.csv')

unless File.exist?(csv_path)
  puts "CSV file not found at: #{csv_path}"
  raise "Missing CSV file: #{csv_path}"
end

CSV.foreach(csv_path, headers: true) do |row|
  name = row['provincia'] || row['name'] || row[0]
  next if name.blank?

  Province.find_or_create_by!(name: name.strip) do |p|
    p.created_at = Time.current
    p.updated_at = Time.current
  end
end

puts "Provinces seeded into table `region` successfully"

# -----------------------------
# Seed Districts from CSV
# -----------------------------
require 'csv'

puts "Seeding Districts from CSV..."

csv_path = Rails.root.join('db', 'seeds', 'districts_from_2025.csv')

unless File.exist?(csv_path)
  puts "CSV file not found at: #{csv_path}"
  raise "Missing CSV file: #{csv_path}"
end

# Criar índice das provinces existentes na tabela `region`
province_index = Province.all.each_with_object({}) do |prov, h|
  h[prov.name.strip] = prov.region_id
end

created = 0
skipped = 0

CSV.foreach(csv_path, headers: true) do |row|
  province_name = row['provincia']&.strip
  district_name = row['distrito']&.strip

  next if province_name.blank? || district_name.blank?

  region_id = province_index[province_name]

  if region_id.nil?
    puts "⚠ Province not found: #{province_name}"
    skipped += 1
    next
  end

  District.find_or_create_by!(name: district_name, region_id: region_id)
  created += 1
end

puts "Districts seeded successfully. Created/ensured: #{created}, Skipped: #{skipped}"

# -----------------------------
# Seed Locations (Facilities) from CSV (2025)
# -----------------------------
require 'csv'

puts "Seeding Locations from CSV..."

csv_path = Rails.root.join('db', 'seeds', 'locations_from_2025.csv')
raise "Missing CSV file: #{csv_path}" unless File.exist?(csv_path)

creator_id = (ENV['SEED_CREATOR_ID'] || 1).to_i

# Provinces index (table `region`)
province_index = Province.all.each_with_object({}) do |prov, h|
  h[prov.name.to_s.strip.upcase] = prov.region_id
end

# District index: (region_id + district_name) -> district_id
district_index = District.all.each_with_object({}) do |d, h|
  key = "#{d.region_id}|#{d.name.to_s.strip.upcase}"
  h[key] = d.district_id
end

created = 0
updated = 0
skipped = 0

CSV.foreach(csv_path, headers: true) do |row|
  code          = row['codigo']&.strip
  name          = row['unidade_sanitaria']&.strip
  provincia     = row['provincia']&.strip
  distrito      = row['distrito']&.strip
  latitude      = row['latitude']&.strip
  longitude     = row['longitude']&.strip

  tipo          = row['tipo']&.strip
  tipo_de_us    = row['tipo_de_us']&.strip
  nivel         = row['nivel']&.strip
  classificacao = row['classificacao']&.strip
  maternidade   = row['maternidade_sn']&.strip

  next if code.blank? || name.blank? || provincia.blank? || distrito.blank?

  region_id = province_index[provincia.upcase]
  if region_id.nil?
    puts "⚠ Province not found in `region`: #{provincia} (code=#{code}, name=#{name})"
    skipped += 1
    next
  end

  district_id = district_index["#{region_id}|#{distrito.upcase}"]
  if district_id.nil?
    puts "⚠ District not found: #{provincia} / #{distrito} (code=#{code}, name=#{name})"
    skipped += 1
    next
  end

  # guarda detalhes extras no description (opcional)
  desc_parts = []
  desc_parts << "tipo=#{tipo}" if tipo.present?
  desc_parts << "tipo_de_us=#{tipo_de_us}" if tipo_de_us.present?
  desc_parts << "nivel=#{nivel}" if nivel.present?
  desc_parts << "classificacao=#{classificacao}" if classificacao.present?
  desc_parts << "maternidade_sn=#{maternidade}" if maternidade.present?
  description = desc_parts.any? ? desc_parts.join(' | ') : nil

  # Estratégia de dedupe: code é o melhor identificador
  loc = Location.find_or_initialize_by(code: code)
  is_new = loc.new_record?

  loc.name        = name
  loc.district_id = district_id
  loc.creator     = creator_id
  loc.voided      = 0 if loc.voided.nil?

  # latitude/longitude na tua tabela são varchar, então pode salvar string
  loc.latitude    = latitude if latitude.present?
  loc.longitude   = longitude if longitude.present?

  loc.description = description if description.present?

  loc.created_at ||= Time.current
  loc.updated_at  = Time.current

  loc.save!

  is_new ? created += 1 : updated += 1
end

puts "Locations seeded. Created: #{created}, Updated: #{updated}, Skipped: #{skipped}"

# === Add foreign key constraints ===
connection = ActiveRecord::Base.connection

begin
  connection.execute <<-SQL
    ALTER TABLE mailer_districts
    ADD CONSTRAINT fk_mailer_districts_district
    FOREIGN KEY (district_id)
    REFERENCES districts(district_id);
  SQL

  puts "Added foreign key to mailer_districts → districts"
rescue => e
  puts "Could not add foreign key to mailer_districts: #{e.message}"
end

begin
  connection.execute <<-SQL
    ALTER TABLE mailing_logs
    ADD CONSTRAINT fk_mailing_logs_district
    FOREIGN KEY (district_id)
    REFERENCES districts(district_id);
  SQL

  puts "Added foreign key to mailing_logs → districts"
rescue => e
  puts "Could not add foreign key to mailing_logs: #{e.message}"
end

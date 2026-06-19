desc 'Drop master-only tables on proxy instances after schema load'
Rake::Task['db:schema:load'].enhance do
  if ENV['MASTER'] == 'false'
    connection = ActiveRecord::Base.connection
    if connection.table_exists?(:npids)
      connection.drop_table(:npids)
      puts 'Proxy mode: dropped npids table (master-only table)'
    end
  end
end

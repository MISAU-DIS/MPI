class AddIdPrimaryKeyToNpids < ActiveRecord::Migration[7.0]
  def up
    if table_exists?(:npids)
      unless column_exists?(:npids, :id)
        execute "ALTER TABLE `npids` DROP PRIMARY KEY"
        
        execute "ALTER TABLE `npids` ADD `id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST"
        
        puts "Successfully added ID primary key to npids."
      else
        puts "ID column already exists on npids. Skipping."
      end
    else
      puts "Table npids does not exist (likely running as Proxy). Skipping."
    end
  end

  def down
    if table_exists?(:npids) && column_exists?(:npids, :id)
      execute "ALTER TABLE `npids` DROP PRIMARY KEY"
      execute "ALTER TABLE `npids` DROP COLUMN `id`"
      execute "ALTER TABLE `npids` ADD PRIMARY KEY (`npid`)"
    end
  end
end
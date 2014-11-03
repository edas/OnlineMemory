require 'yaml'
load "./twitter.rb"


YAML.load_file("settings.yml").each_pair do |name, config|
  cfg = config["twitter"]
  puts "For #{name}:"
  eraser = OnlineMemory::Twitter::OldTweetsEraser.new
  eraser.client = cfg['credentials']
  # nil if you don't want backup
  eraser.storage = cfg['storage_path']
  eraser.erase_older_than(cfg['expiration_time'])
  puts ""
end

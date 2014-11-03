require 'yaml'
load "./twitter.rb"


cfg = YAML.load_file("settings.yml")["twitter"]



eraser = OnlineMemory::Twitter::OldTweetsEraser.new
eraser.client = cfg['credentials']

# nil if you don't want backup
eraser.storage = cfg['storage_path']


eraser.erase_older_than(cfg['expiration_time'])
require 'yaml'
load "./twitter.rb"


cfg = YAML.load_file("settings.yml")["twitter"]

OnlineMemory::Twitter.erase_old_tweets(
  cfg['credentials'],
  cfg['expiration_time'], 
  cfg['storage_path']
)
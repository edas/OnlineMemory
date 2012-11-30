require 'yaml'
load "./twitter.rb"


cfg = YAML.load_file("settings.yml")["twitter"]

eraser = OnlineMemory::Twitter::OldTweetsEraser.new
eraser.client = client = OnlineMemory::Twitter::RateLimitedClient.new( cfg['credentials'] )
screen_name = client.screen_name
archive_file = "#{screen_name}/#{screen_name}-tweets.txt"
tweets_archive = OnlineMemory::Twitter::TweetArchiveFile.new( archive_file )
eraser.timeline = OnlineMemory::Twitter::FakeTimeline.new( tweets_archive, client)
eraser.storage = OnlineMemory::Twitter::Storage.new( cfg['storage_path'] )

eraser.erase_older_than(cfg['expiration_time'])




# $stdout.write "Backup and delete "
# processed = 0
# begin
#   archive.each_tweet_id do |id|
#     tries = 0
#     begin
#       tries += 1
#       tweet = client.status(status_id)
#       storage.store( tweet )
#       date = DateTime.parse tweet.attrs[:created_at]
#       if date < expiration
#         client.tweet_destroy( tweet.attrs[:id] ) 
#         $stdout.write "."
#         processed += 1
#       end
#     rescue ::Twitter::Error::NotFound => error
#       $stdout.write "x"
#     rescue ::Twitter::Error::ClientError => error
#       if tries < 3
#         sleep 250
#         $stderr.write "(ClientError #{error.to_s} #{tries})"
#         client = OnlineMemory::Twitter::RateLimitedClient.new(cfg['credentials'])
#         client.wait_if_overloaded = 250
#         retry
#       else
#         raise
#       end
#     end
#   end
# rescue ::Twitter::Error::TooManyRequests => error
#   $stderr.write "(too many requests)"
# ensure
#   $stdout.write " " + processed.to_s + " tweets" 
# end

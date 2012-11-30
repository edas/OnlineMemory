require "rubygems"
require "bundler/setup"
require 'yaml'
require 'twitter'
require 'json'
require 'active_support'
require "tzinfo"
require "active_support/time_with_zone"
require "active_support/duration"
require "active_support/time"

module OnlineMemory
  module Twitter
    
    def self.erase_old_tweets(client, expiration=0, storage=nil)
      eraser = OldTweetsEraser.new
      eraser.client = client
      eraser.storage = storage
      return eraser.erase_older_than(expiration)
    end

    def self.backup_new_tweets(client, storage)
      raise "TODO"
    end

    class OldTweetsEraser
      attr_reader :client
      attr_reader :storage
      attr_writer :timeline
      attr_accessor :ignore_missing
      attr_accessor :wait_if_overloaded

      def initialize
        @ignore_missing = true
        @wait_if_overloaded = false
      end

      def storage=(val)
        if val.respond_to? :store
          @storage = val
        else
          @storage = Storage.new( val )
        end
      end

      def timeline
        @timeline ||= Timeline.new( client )
      end

      def client=(val)
        if val.respond_to? :verify_credentials
          @client = val
        else
          @client = RateLimitedClient.new( client )
        end
      end

      def erase_older_than(expiration)
        expiration = DateTime.now - expiration.seconds unless expiration.respond_to? :acts_like_date? and expiration.acts_like_date?
        processed = 0
        $stdout.write (storage ? "Backup and delete " : "Delete ")
        begin
          timeline.each_older_than(expiration) do |tweet|
            storage.store( tweet ) if storage
            client.tweet_destroy( tweet.attrs[:id] ) 
            $stdout.write "."
            processed += 1
          end
        ensure
          $stdout.write " \nProcessed " + processed.to_s + " tweet(s)\n" 
        end
        return true
      end

    end


    class RateLimitedClient 

      attr_accessor :max_retries
      attr_accessor :wait_if_overloaded
      attr_accessor :wait_if_clienterror

      def initialize(*options)
        @client = Client.new(*options)
        @max_retries = 5
        @wait_if_overloaded = 250
        @wait_if_clienterror = 250
      end

      def method_missing(m, *args, &block)
        rate_limit(m, *args, &block)
      end

      def respond_to?(m)
        @client.respond_to?(m)
      end

    private 

      def manageable_error?(error)
        case error
        when ::Twitter::Error::TooManyRequests
          { 
            cause: "too many requests" , 
            wait: error.rate_limit.reset_in + 15 
          }
        when ::Twitter::Error::ServiceUnavailable
          { 
            cause: "twitter overloaded" , 
            wait: @wait_if_overloaded 
          }
        when ::Twitter::Error::ClientError
          if error.to_s.match(/Connection reset by peer/)
            { 
              cause: "connection reset by peer" , 
              wait: @wait_if_clienterror ,
              exec: Proc.new { self.reset_connection! }
            }
          elsif error.to_s.match(/Timeout::Error/)
            {
              cause: "twitter timeout",
              wait: @wait_if_clienterror ,
              exec: Proc.new { self.reset_connection! }
            }
          else
            false
          end
        when ::Timeout::Error
        else
          false
        end  
      end

      def rate_limit(method, *params, &block)
        tries = 0
        begin
          tries += 1
          result = @client.__send__(method,*params, &block)
        rescue => error
          data = manageable_error?(error)
          raise unless data
          if tries > @max_retries or not data[:wait] or data[:wait] == 0
            $stderr.write "(#{data[:cause]})\n"
            raise
          else
            $stderr.write "(#{data[:cause]}, try #{tries}, sleeping #{data[:wait]})"
            sleep (data[:wait])
            data[:exec].call if data[:exec]
            retry
          end
        end
        result
      end

    end

    class TweetArchiveFile

      attr_accessor :file
      def initialize(file)
        @file = file
      end

      def each_tweet_id
        io = File.open(@file)
        io.each_line do |line|
          if /^status_id: (\d+)/.match(line)
            yield $1
          end
        end
      end

      alias_method :each, :each_tweet_id

    end

    class Client < ::Twitter::Client

      def screen_name
        unless @screen_name
          @screen_name = verify_credentials.attrs[:screen_name]
        end
        @screen_name
      end

      def reset_connection!
        @connection = nil
      end

    end

    class Storage

      attr_accessor :directory

      def initialize(directory)
        @directory = directory
      end

      def store(tweet) 
        File.write path_from_tweet(tweet), content_from_tweet(tweet)
      end

      def stored?(tweet)
        File.exists? path_from_tweet(tweet)
      end

      def remove(tweet)
        File.delete path_from_tweet(tweet)
      end

    private 

      def content_from_tweet(tweet)
        JSON.generate(tweet.attrs)
      end

      def path_from_tweet(tweet)
        @directory + "/" + id_from_tweet(tweet) + ".json"
      end

      def id_from_tweet(tweet)
        tweet.attrs[:id_str]
      end

    end

    class Timeline

      def initialize(client, screen_name=nil)
        @twitter = client
        @screen_name = screen_name || client.screen_name
      end

      def each(options={})
        tweets = fetch_first_tweets(options)
        while tweets and tweets.count > 0
          tweets.each do |tweet|
            yield tweet
          end
          tweets = fetch_next_tweets
        end 
      end

      def each_older_than(limit, options={})
        each do |tweet|
          date = DateTime.parse tweet.attrs[:created_at]
          yield tweet if date < limit
        end
      end

    private

      def fetch_first_tweets(options={})
        @end_of_tweets = false
        fetch_in_timeline
      end

      def fetch_next_tweets(options = {})
        return false if @end_of_tweets
        options[:max_id] ||= @next_tweet - 1
        fetch_in_timeline
      end

      def fetch_in_timeline(options = {})
        options[:count] ||= 200
        options[:contributor_details] = true
        options[:include_my_retweet] = true
        options[:include_rts] = true
        options[:include_entities] = true
        options[:max_id] = @next_tweet - 1 if @next_tweet
        tweets = real_fetch_in_timeline(options)
        tweets ||= [ ]
        @end_of_tweets = true if tweets.count == 0
        @next_tweet = tweets.last.attrs[:id] if tweets.count > 0
        tweets
      end

      def real_fetch_in_timeline(options)
        @twitter.user_timeline(@screen_name, options)
      end

    end

    class FakeTimeline < Timeline

      attr_reader :tweet_ids
      attr_accessor :ignore_missing

      def initialize(tweet_ids, *params)
        super(*params)
        self.tweet_ids = tweet_ids
        self.ignore_missing = true
      end

      def tweet_ids=(val)
        @enum = nil
        @tweet_ids = val
      end

      def tweet_ids_enum
        @enum ||= @tweet_ids.to_enum(:each_tweet_id)
      end

    private

      def real_fetch_in_timeline(options)
        begin
          begin
            tweet_id = tweet_ids_enum.next
          rescue StopIteration => e
            return nil
          end
          tweets = [ @twitter.status(tweet_id, options) ]
        rescue ::Twitter::Error::NotFound => error
          raise unless @ignore_missing
          $stderr.write "#"
          retry
        end
        return tweets
      end

    end
  end
end

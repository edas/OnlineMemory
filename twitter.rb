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
      storage = Storage.new( storage ) if storage and not storage.respond_to? :store
      client = RateLimitedClient.new( client ) unless client.respond_to? :verify_credentials
      timeline = Timeline.new( client )
      expiration = DateTime.now - expiration.seconds unless expiration.respond_to? :acts_like_date? and expiration.acts_like_date?
      processed = 0
      begin
        $stdout.write "Backup and delete "
        timeline.each_older_than(expiration) do |tweet|
          storage.store( tweet ) if storage
          client.tweet_destroy( tweet.attrs[:id] ) 
          $stdout.write "."
        end
      rescue ::Twitter::Error::TooManyRequests => error
        $stderr.write "(too many requests)"
        return false
      ensure
        $stdout.write " " + processed.to_s + " tweets" 
      end
      return true
    end

    def self.backup_new_tweets(client, storage)
      raise "TODO"
    end

    class RateLimitedClient 

      attr_accessor :max_retries

      def initialize(*options)
        @client = Client.new(*options)
        @max_retries = 5
      end

      def method_missing(m, *args, &block)
        rate_limit(m, *args, &block)
      end

      def respond_to?(m)
        @client.respond_to?(m)
      end

    private 

      def rate_limit(method, *params, &block)
        tries = 0
        begin
          tries += 1
          result = @client.__send__(method,*params, &block)
        rescue ::Twitter::Error::TooManyRequests => error
          $stderr.write "(too many requests #{tries})"
          if tries <= @max_retries
            $stderr.write "(sleeping #{error.rate_limit.reset_in})"
            sleep error.rate_limit.reset_in
            retry
          else
            raise
          end
        end
        result
      end

    end

    class Client < ::Twitter::Client

      def screen_name
        unless @screen_name
          @screen_name = verify_credentials.attrs[:screen_name]
        end
        @screen_name
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
        tweets = @twitter.user_timeline(@screen_name, options) || [ ]
        @end_of_tweets = true if tweets.count == 0
        @next_tweet = tweets.last.attrs[:id] if tweets.count > 0
        tweets
      end

    end
  end
end

OnlineMemory
============

Script to backup and delete old tweets.

## Configuration

Go to <http://dev.twitter.com>. Create a new application. Call it for example "remove-tweet", use the description you want, and specify any website.

When it's done, go to "Settings" > "Application type" and specify "Read, Write and Access direct messages" (at least Read and Write). Validate.

Once everything is ok, come back to "Details" and create a new access token.

Now, modify settings.yml with the values specified in dev.twitter.com.

## Dependances

``` $ bundle install ```

## Execute

``` $ ruby backup.rb ```

## More Information

To go further the 3200th tweet, you have to fill a formal request
to Twitter, then use the data to delete each tweet by its id
See <https://www.privacyinternational.org/blog/what-does-twitter-know-about-its-users-nologs>
You may have to be resident in the EU for that.
Shoes.setup do
  gem "xmpp4r-simple"
  gem "json_pure"
end

require "xmpp4r-simple"
require "yaml"
require "net/http"
require "json/pure"

class Twitson  
  @@twitter = 'twitter.com'
  @@friends_path = '/statuses/friends_timeline.json'
  @@show_path = '/users/show/'
  
  def initialize(username='', password='')
    @username = username
    @password = password
  end
  
  def friends_timeline
    get(@@friends_path)
  end
  
  def show(user)
    get("#{@@show_path}#{user}.json")
  end

  protected
  
    def get(path)
      rvalue = []
      begin
        response = Net::HTTP.start(@@twitter, 80) do |http|
          req = Net::HTTP::Get.new(path)
          req.basic_auth(@username, @password) if !@username.empty?
          http.request(req)
        end
        raise StandardError unless response.message == 'OK'
        rvalue = JSON.load(response.body)
      rescue StandardError => bang
        error bang
      end
      rvalue
    end  
end

class HTML
  
  def self.html(message)
    message = message.gsub(/&(\w+);/) { |m|
       case $1
         when 'apos': "'"
         when 'lt': "<"
         when 'gt': ">"
         when 'nbsp': " "
         when 'quot': "\\\""
         else m
       end
    }
    message.gsub(/&amp;/, "&") 
  end
  
end

class Tweet
  
  def self.replace(app, flow, what, avatar=nil, type=:normal)
    flow.clear { fill(app, what, avatar, type) }
  end
    
  def self.create(app, what, avatar=nil, type=:normal)
    app.flow :margin_top => 5, :margin_left => 5, :margin_right => 5, :width => 1.0 do 
      fill(app, what, avatar, type)
    end
  end
  
  private
  
    def self.fill(app, what, avatar=nil, type=:normal)
      color = '#fff'
      if type == :system
        app.background rgb(30, 30, 180, 180), :curve => 8
        what = "twitter: " + what
      elsif type == :direct
        app.background rgb(255, 255, 255, 150), :curve => 8
        color = '#000'
      elsif type == :you
        app.background rgb(0, 102, 0, 120), :curve => 8
      else
        app.background rgb(0, 0, 0, 120), :curve => 8
      end

      app.stack :width => 58, :margin => 5 do
        avatar = "default_profile_normal.png" if avatar.nil?
        app.image avatar, :width => 48, :height => 48, :curve => 4
      end
      app.stack :width => -58, :margin => 5 do
        eval("app.para #{linkinizer(what)}, :stroke => '#{color}', :margin => 0, :font => 'Arial 12px'")
      end     
    end
  
    def self.linkinizer(message)
      message.gsub!("\\", "\\\\")
      message.gsub!("\"", "\\\"")
      index = message.index(":")
      result = "app.span(app.strong(\"#{message[0, index]}\"), :font => '15px'), "
      message = message[index+1, message.length-index]
      if /http:\/\/\S+|@\w+/i =~ message
        pindex = 0
        message.scan(/http:\/\/\S+|@\w+/i) do |l|
          index = message.rindex(l)
          result << "\"#{message[pindex, index-pindex]}\"," if index > 0
          result << " app.link(\"#{l}\", :click => "
          if /@(\S+)/ =~ l
            result << "\"http://twitter.com/#{l[/@(\w+)/,1]}\"),"
          else
            result << "'#{l}'),"
          end
          pindex = index + l.length
        end
        result << " \"#{$'}\""
      else
        result << " \"" + message + "\""
      end    
      result = result
      result.gsub(/"[^"]+"/) { |m| HTML.html(m) }
    end
  
end

class Twingle < Shoes
  
  url "/", :setup
    
  def check_rate_limit
    @ratelimitmessage.hide
    return
    if @twitson && @twitson.rate_limit_exceeded?
      @ratelimitmessage.show
    else
      @ratelimitmessage.hide
    end
  end

  def load_avatars
    @avatars = {}
    if File.exists?('avatars.yaml')
      @avatars = YAML.load_file('avatars.yaml')
    end
  end

  def load_current_tweets
    unless @settings["twitter"].nil?
      @twitson = Twitson.new(@settings["twitter"]["username"], @settings["twitter"]["password"])
      current_tweets = @twitson.friends_timeline
      current_tweets.reverse_each do |tweet|
        username = tweet['user']['screen_name']
        @avatars[username] = tweet["user"]["profile_image_url"]
        twit("#{username}: #{tweet['text']}", username)
      end
      @avatars['You'] = @avatars[@settings["twitter"]["username"]] if @settings["twitter"]
      save_avatars  
    end
  end
  
  def save_avatars
    File.open( 'avatars.yaml', 'w' ) do |out|
      YAML.dump(@avatars, out )
    end
  end
  
  def avatar(user)
    value = @avatars[user]
    unless value
      result = @twitson.show(user)
      value = result["profile_image_url"]
      @avatars[user] = value
      save_avatars
    end
    value
  end
    
  def sound?
    return @settings["sound"]
  end

  def max_tweets
    return !@settings["maxtweets"].nil? && @settings["maxtweets"].integer? ? @settings["maxtweets"].to_i : 10;
  end

  def twit(what, user=nil, type=:normal)
    type = :you if type == :normal && (user.casecmp('You') == 0 || user.casecmp(@settings["twitter"]["username"]) == 0)

    twits = @tweets.contents
    if twits.length == max_tweets + 1
      twits.insert(0, Tweet.replace(self, twits.delete_at(max_tweets), what, avatar(user), type))
    else
      @tweets.prepend { Tweet.create(self, what, avatar(user), type) }
    end
    @tweets.show
  end

  def send_say_it 
    text = @say_it.text.chomp
    if text.length > 0
      @jabber.deliver("twitter@twitter.com", @say_it.text)
      twit("You: " + @say_it.text, "You")
    end

    @say_it.text = ''
    check_leftover
  end
  
  def check_leftover
    leftover_count = (140-@say_it.text.to_s.length)
    @leftover_value.style(:stroke => leftover_count < 0 ? red : black)
    @leftover_value.replace(strong(leftover_count.to_s))
  end

  def setup
    @settings = YAML.load_file('twingle.yaml')
    @jabber = Jabber::Simple.new(@settings["jabber"]["jid"], @settings["jabber"]["password"]) 
    @tracker = []    
    
    background "wood.jpg"
    flow :width => -gutter() do 
      @connected = stack :width => 1.0, :height => 5, :scroll => true do
        background '#f00'
      end

      @header = stack do
        flow do
          image "logo.png", :margin => 5
          stack :width => 100, :right => 0, :top => 5
        end
      end
  
      @babblebox = stack do
        flow :margin => 5 do
          @say_it = edit_box :margin => 5, :width => -110, :height => 50, :size => 9 do
            check_leftover
            if @say_it.text[-1] == ?\n
              send_say_it
            end          
          end
          button "Say it", :width => 100, :right => 5, :top => 5 do
            send_say_it
          end
          @leftover = stack :width => 50, :height => 35, :right => 100, :scroll => true, :top => -30 do
            background "leftover.png"
            @leftover_value = para strong('140'), :margin => 5, :align => 'center'
          end
          @leftover.hide          
        end 
      end 
      
      @separator = stack :height => 1, :width => 1.0, :scroll => true do
        background black
      end

      @tweetswrapper = stack :height => 420, :width => 1.0, :scroll => true do
        background rgb(0,0,0,127)
        @tweets = stack :width => -gutter(), :margin_bottom => 5
      end
      
      @ratelimitmessage = stack do
        #background rgb(0,0,0,127)
        para strong('Rate Limit Exceeded'), :margin => 5, :stroke => '#fc0', :font => '12px'
      end
    end
    
    if sound?
      @chat_sound = video 'chat2.wav', :width => 0, :height => 0
      @direct_sound = video 'direct.wav', :width => 0, :height => 0
    end

    load_avatars
    load_current_tweets
    check_rate_limit

    every(2) do
      if @jabber.connected? 
        @connected.clear do
          background '#0C0'
        end

        @first = true
        @jabber.received_messages do |m|
          @chat_sound.play if @first && sound?
          @first = false
          if m.from == "twitter@twitter.com" && m.type == :chat
            unless (m.body.index(':').nil?)
              unless m.body.index("Direct from").nil?
                @direct_sound.play if sound?
                twit(m.body, m.body[0, m.body.index(":")].sub(/Direct from /, ""), :direct)
              else
                @chat_sound.play if @first && sound?
                twit(m.body, m.body[0, m.body.index(":")])
              end
            else
              @chat_sound.play if @first && sound?
              twit(m.body, 'twitter', :system)
            end
            @first = false
          end 
        end
      else
        @connected.clear do
          background '#f00'
        end
      end    
    end

    animate(5) do
      fix_sizes
    end  

    every(5) do
      check_rate_limit
    end
  end
  
  def fix_sizes()
    if @appHeight != $app.height || @ratelimitmessageHeight != @ratelimitmessage.height
      @appHeight = $app.height
      @ratelimitmessageHeight = @ratelimitmessage.height

      @tweetswrapper.hide
      @tweetswrapper.show
      @tweetswrapper.height = $app.height - @connected.height - @header.height - @babblebox.height - @ratelimitmessage.height - 1
    end
  end
end

$app = Shoes.app :width => 400, :height => 600, :resizable => true, :title => "Twingle, experience twitter"
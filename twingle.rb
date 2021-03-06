Shoes.setup do
  gem "xmpp4r-simple"
  gem "json_pure"
end

require "xmpp4r-simple"
require "yaml"
require "net/http"
require "json/pure"
require 'thread'

class Twitson  
  @@twitter = 'twitter.com'
  @@friends_path = '/statuses/friends_timeline.json'
  @@show_path = '/users/show/'
  
  def initialize(username='', password='')
    @username = username
    @password = password
  end
  
  def friends_timeline
    get(@@friends_path, [])
  end
  
  def show(user)
    get("#{@@show_path}#{user}.json", {})
  end

  def rate_limit_exceeded?
      File.exists?('rate_limit_delay.yaml')
  end

  protected
  
    def get(path, default)
      rvalue = default
      
      unless wait_for_rate_limit?
        begin
          response = Net::HTTP.start(@@twitter, 80) do |http|
            req = Net::HTTP::Get.new(path)
            req.basic_auth(@username, @password) if !@username.empty?
            http.request(req)
          end
          if response.message == 'Bad Request' 
            evalue = JSON.load(response.body)
            raise StandardError if evalue['error'].index('Rate limit') === nil
            # rate limit exceeded
            warn('rate limit exceeded')
            extend_rate_limit
            return rvalue
          else
            raise StandardError unless response.message == 'OK'
          end
          rvalue = JSON.load(response.body)
          clear_rate_limit
        rescue StandardError => bang
          error(response.body)
          puts bang
        end
      end
      rvalue
    end  
    
    def extend_rate_limit
      delay = { "until" => Time.now.to_i + 300 }
      delay = { "delay" => delay } # wait 5 min
      File.open( 'rate_limit_delay.yaml', 'w' ) do |out|
        YAML.dump(delay, out)
      end
    end

    def wait_for_rate_limit?
      wait = get_rate_limit_delay() > Time.now.to_i
    end

    def clear_rate_limit
      File.delete 'rate_limit_delay.yaml' if File.exists?('rate_limit_delay.yaml')
    end
  
    def get_rate_limit_delay
      delay = { }
      if File.exists?('rate_limit_delay.yaml')
        delay = YAML.load_file('rate_limit_delay.yaml')
      end
      
      result = 0
      unless delay["delay"].nil?
        result = delay["delay"]["until"].to_i unless delay["delay"]["until"].nil?
      end 
      result   
    end

end

class Twingle < Shoes   
  url "/", :setup
  
  def setup
    style(Link, :stroke => '#09C')
    style(LinkHover, :stroke => '#000', :bold => true)

    # load settings
    @settings = YAML.load_file('twingle.yaml')
    
    # set you-value
    @you = 'You'
    unless @settings["twitter"].nil? 
      @you = @settings["twitter"]["username"].capitalize unless @settings["twitter"]["username"].nil?
    end  

    build_ui
    load_avatars
  
    # load previous tweets. Do this in seperate thread because the twitter api can cause quite some lag.
    @twit_mutex = Mutex.new
    Thread.new do
      #sleep 0.5
      load_current_tweets
      fix_sizes true
    end

    # start loop
    @jabber = Jabber::Simple.new(@settings["jabber"]["jid"], @settings["jabber"]["password"]) 
    @count = 0

    #do_stuff
    every(1) do
      do_stuff
    end
  end

  def do_stuff
    poll_jabber
    check_rate_limit
    fix_sizes
  end
  
  def poll_jabber
    if @jabber && @jabber.connected? 
      @first = true
      #@twit_mutex.synchronize do
        @jabber.received_messages do |m|
          if m.from == "twitter@twitter.com" && m.type == :chat
            @count += 1
            unless (m.body.index(':').nil?)
              if m.body.index("Direct from").nil?
                @chat_sound.play if @first && sound?
                twit(m.body, m.body[0, m.body.index(":")])
              else
                @direct_sound.play if sound?
                twit(m.body, m.body[0, m.body.index(":")].sub(/Direct from /, ""), ":direct")
              end
            else
              @chat_sound.play if @first && sound?
              twit(m.body, 'twitter', ':system')
            end
            @first = false
          end 
        end
      #end
      @connected.clear do
        background '#0C0' .. '#444'
      end
    else
      @connected.clear do
        background '#f00' .. '#444'
      end
    end    
  end
  
  def check_rate_limit
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
      changed = false
      @twit_mutex.synchronize do
        current_tweets.reverse_each do |tweet|
          username = tweet['user']['screen_name']
          if @avatars[username] != tweet["user"]["profile_image_url"]
            @avatars[username] = tweet["user"]["profile_image_url"]
            changed = true
          end
          twit("#{username}: #{tweet['text']}", username)
          sleep 0.01
        end
      end
      save_avatars if changed
    end
  end
  
  def save_avatars
    File.open( 'avatars.yaml', 'w' ) do |out|
      YAML.dump(@avatars, out )
    end
  end
  
  def avatar(user)
    value = nil

    if user && @avatars
      # some special cases
      if user == ':system'
        user = 'twitter'
      elsif user == 'You' && @settings["twitter"] 
        user = @settings["twitter"]["username"]
      end

      # check cached values
      value = @avatars[user]
      unless value
        # not found, check for special case (tracking through IM)
        user = user[/^\(?(.+?)\)?$/,1]        
        result = @twitson.show(user)
        
        # if found...
        unless result["profile_image_url"].nil?
          value = result["profile_image_url"]
          if value
            # store avatar in cache
            @avatars[user] = value
            save_avatars
          end
        end
      end
    end

    # safeguard    
    value.nil? ? "default_profile_normal.png" : value
  end
    
  def sound?
    return @settings["sound"]
  end

  def twit(what, user=nil, type=':normal')
    @tweets.prepend {     
      flow :margin_top => 5, :margin_left => 5, :margin_right => 5, :width => 1.0 do 
        if type == ':normal'
          isYou = user == 'You' 
          unless @settings["twitter"].nil? 
            isYou = isYou || (user.casecmp(@settings["twitter"]["username"]) == 0) unless @settings["twitter"]["username"].nil?
          end
        end

        color = '#fff'
        if type == ':system'
          background "#191616" .. "#663636", :radius => 8
          what = "twitter: " + what
        elsif type == ':direct'
          background "#969696" .. "#C6C6C6", :radius => 8
        color = '#000'
        elsif isYou
          background "#191616" .. "#366636", :radius => 8
        elsif user[0,1] == '('
          background "#191616" .. "#363666", :radius => 8
        else
          background "#191616" .. "#363636", :radius => 8
        end
        stack :width => 58, :margin => 5 do
          avatar = avatar(user)
          image avatar, :width => 48, :height => 48, :radius => 4
        end
        stack :width => -58, :margin => 5 do
          eval("para #{linkinizer(what)}, :stroke => '#{color}', :margin => 0, :font => 'Arial 12px'")
        end 
      end
    }
  end

  def html(message)
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
  
  def linkinizer(message)
    index = message.index(":")
    result = "span(strong(\"#{message[0, index]}\"), :font => '15px'), "
    message = message[index+1, message.length-index]

    if /http:\/\/\S+|@\w+/i =~ message
      pindex = 0
      message.scan(/http:\/\/\S+|@\w+/i) do |l|
        index = message.rindex(l)
        result << "\"#{message[pindex, index-pindex]}\"," if index > 0
        result << " strong(link(\"#{l}\", :click => "
        if /@(\S+)/ =~ l
          result << "\"http://twitter.com/#{l[/@(\w+)/,1]}\")),"
        else
          result << "'#{l}')),"
        end
        pindex = index + l.length
      end
      result << " \"#{$'}\""
    else
      result << " \"" + message + "\""
    end    

    result = result
    result.gsub(/"[^"]+"/) { |m| html(m) }
  end

  def send_say_it 
    text = @say_it.text.chomp
    if text == "console" 
      Shoes.show_log
    elsif text.length > 0
      @jabber.deliver("twitter@twitter.com", @say_it.text)
      @twit_mutex.synchronize do
        twit(@you + ": " + text, @you)
      end
    end
    @say_it.text = ''
    check_leftover
  end
  
  def check_leftover
    leftover_count = (140-@say_it.text.to_s.length)
    @leftover_value.style(:stroke => leftover_count < 0 ? red : black)
    @leftover_value.replace(strong(leftover_count.to_s))
  end

  def build_ui
    if sound?
      @chat_sound = video 'chat2.wav', :width => 0, :height => 0
      @direct_sound = video 'direct.wav', :width => 0, :height => 0
    end
    
    background "#000"
    flow :width => -gutter() do 
      @connected = stack :width => 1.0, :height => 5, :scroll => true do
        background '#f00' .. '#444'
      end
      
      @header = stack do
        background "#444" .. "#666"
        flow do
          image "logo.png", :margin => 5
          stack :width => 100, :right => 0, :top => 5 do
            #@status = para strong("> <"), :stroke => '#F00'
          end
        end
      end
    
      @babblebox = stack do
        background "#666" .. "#000"
        flow :margin => 5 do
          @say_it = edit_box :margin => 5, :width => -110, :height => 50, :size => 9 do
            check_leftover
            send_say_it if @say_it.text.index("\n") != nil
          end
          button "Say it", :width => 100, :right => 5, :top => 5 do
            send_say_it
          end
          @leftover = stack :width => 50, :height => 35, :right => 100, :scroll => true, :top => -30 do
            background "leftover.png"
            @leftover_value = para strong('140'), :margin => 5, :align => 'center'
          end          
        end 
      end 
      
      stack do 
        @tweetswrapper = stack :height => 420, :width => 1.0, :scroll => true do
          background "#000"
          @tweets = stack :width => -gutter()
        end
        
        @ratelimitmessage = stack do
          background "#000" .. "#600"
          para strong('Rate Limit Exceeded'), :margin => 5, :stroke => '#fc0', :font => '12px'
        end
      end
    end
  end
    
  def fix_sizes(force=false)
    
    if force || @appHeight != $app.height || @ratelimitmessageHeight != @ratelimitmessage.height
      @appHeight != $app.height
      @ratelimitmessageHeight != @ratelimitmessage.height
      @tweetswrapper.height = $app.height - @connected.height - @header.height - @babblebox.height - @ratelimitmessage.height 
    end
    
    if force || @tweetsHeight != @tweets.height 
      @tweetsHeight = @tweets.height
      @tweets.width = @tweetswrapper.width-(@tweetswrapper.height < @tweets.height ? gutter() : 0)
    end
  end
end


$app = Shoes.app :width => 400, :height => 600, :resizable => true, :title => "Twingle, experience twitter"  

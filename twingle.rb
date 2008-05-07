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

  def wait_for_rate_limit?
    wait = get_rate_limit_delay() > Time.now.to_i
    File.delete 'rate_limit_delay.yaml' unless wait || !File.exists?('rate_limit_delay.yaml')
    wait
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
            extend_rate_limit
            return rvalue
          else
            raise StandardError unless response.message == 'OK'
          end
          rvalue = JSON.load(response.body)
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

$app = Shoes.app :width => 400, :height => 600, :resizable => true, :title => "Twingle, experience twitter" do  
  
  @settings = YAML.load_file('twingle.yaml')
  @jabber = Jabber::Simple.new(@settings["jabber"]["jid"], @settings["jabber"]["password"]) 
  @count = 0
  
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
    value = "default_profile_normal.png"

    if user && @avatars
      user = @settings["twitter"]["username"] if user == 'You' && @settings["twitter"]
      value = @avatars[user]
      unless value
        result = @twitson.show(user)
        if result["profile_image_url"].nil?
          value = result["profile_image_url"]
          @avatars[user] = value
          save_avatars
        end
      end
    end
    value
  end
    
  def sound?
    return @settings["sound"]
  end

  def twit(what, user=nil)
    @tweets.prepend {     
      flow :margin => 5, :width => 1.0 do 
        background "#191616" .. "#363636", :radius => 8
        stack :width => 58, :margin => 5 do
          avatar = avatar(user)
          image avatar, :width => 48, :height => 48, :radius => 4
          #background avatar, :width => 48, :height => 48, :radius => 4
          #image "spacer.gif", :width => 48, :height => 48
        end
        color = user == 'You' ? '#09f' : '#fff'
        user = @settings["twitter"]["username"] if user == 'You' && @settings["twitter"]
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
        result << " link(\"#{l}\", :click => "
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
    result.gsub(/"[^"]+"/) { |m| html(m) }
  end

  def send_say_it 
    text = @say_it.text.chomp
    if text == "show_log" 
      Shoes.show_log
    else
      @jabber.deliver("twitter@twitter.com", @say_it.text)
      @twit_mutex.synchronize do
        twit("You: " + text, "You")
      end
      @say_it.text = ''
    end
  end
  
  background "#000"
  flow :width => -16 do 
    @header = stack do
      background "#444" .. "#666"
      flow do
        image "logo.png", :margin => 5
        stack :width => 100, :right => 0, :top => 5 do
          @status = para strong("> <"), :stroke => '#F00'
        end
      end
    end
  
    @babblebox = stack do
      background "#666" .. "#000"
      flow :margin => 5 do
        @say_it = edit_box :margin => 5, :width => -110, :height => 50, :size => 9 do
          send_say_it if @say_it.text.index("\n") != nil
        end
        button "Say it", :width => 100, :right => 5, :top => 5 do
          send_say_it
        end
      end 
    end 
    
    stack do 
      @tweetswrapper = stack :height => 420, :width => 1.0, :scroll => true do
        background "#000"
        @tweets = stack :width => -16
      end
      
      @ratelimitmessage = stack do
        background "#000" .. "#600"
        para strong('Rate Limit Exceeded'), :margin => 5, :stroke => '#fc0', :font => '12px'
      end
    end
  end

  animate(1) do
    if @jabber.connected? 
      @first = true
      @twit_mutex.synchronize do
        @jabber.received_messages do |m|
          @chat_sound.play if @first && sound?
          @first = false
          if m.from == "twitter@twitter.com" && m.type == :chat
            @count += 1
            twit(m.body, m.body[0, m.body.index(":")])
          end 
        end
      end
      @status.replace strong(">-<(" + @count.to_s + ")"), :stroke => '#0C0'
    else
      @status.replace strong("> <"), :stroke => '#F00'
    end    
    
    if @twitson && @twitson.wait_for_rate_limit?
      @ratelimitmessage.show
    else
      @ratelimitmessage.hide
    end

    @tweetswrapper.height = $app.height - @header.height - @babblebox.height - @ratelimitmessage.height
    @tweets.width = @tweetswrapper.width-(@tweetswrapper.height < @tweets.height ? 16 : 0)
  end
  
  if sound?
    @chat_sound = video 'chat2.wav', :width => 0, :height => 0
  end
  
  @twit_mutex = Mutex.new
  load_avatars
  Thread.new do
    sleep 0.5
    load_current_tweets
  end
end
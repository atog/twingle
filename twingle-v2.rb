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
  
  def self.replace(app, flow, what, avatar=nil)
    flow.clear { fill(app, what, avatar) }
    flow
  end
    
  def self.create(app, what, avatar=nil)
    app.flow :margin => 5 do 
      fill(app, what, avatar)
    end
  end
  
  private
  
    def self.fill(app, what, avatar=nil)
      app.background "#191616" .. "#363636", :radius => 8
      app.stack :width => 58, :margin => 5 do
        avatar = "default_profile_normal.png" if avatar.nil?
        app.image avatar, :width => 48, :height => 48, :radius => 4
      end
      app.stack :width => -58, :margin => 5 do
        eval("app.para #{linkinizer(what)}, :stroke => '#fff', :margin => 0, :font => 'Arial 12px'")
      end     
    end
  
    def self.linkinizer(message)
      message.gsub!("\"", "'")
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

  def twit(what, user=nil)
    twits = @tweets.contents
    if twits.length == 11
      twits.insert(0, Tweet.replace(self, twits.delete_at(10), what, avatar(user)))
    else
      @tweets.prepend { Tweet.create(self, what, avatar(user)) }
    end
  end

  def send_say_it 
    @jabber.deliver("twitter@twitter.com", @say_it.text)
    twit("You: " + @say_it.text, "You")
    @say_it.text = ''
  end
  
  def setup
    @settings = YAML.load_file('twingle.yaml')
    @jabber = Jabber::Simple.new(@settings["jabber"]["jid"], @settings["jabber"]["password"]) 
    @tracker = []    
    
    background "#000"
    flow :width => -15 do 
      @header = stack do
        background "#fff"
        flow do
          title "Twingle", :width => -110
        end
      end
  
      flow do
        background "#666" .. "#000"
        flow :margin => 5 do
          @say_it = edit_box :margin => 5, :width => -110, :height => 50, :size => 9 do
            if @say_it.text[-1] == ?\n
              send_say_it
            end          
          end
          button "Say it", :width => 100, :right => 5, :top => 5 do
            send_say_it
          end
        end 
      end 
      
      @tweets = stack
    end
    
    if sound?
      @chat_sound = video 'chat2.wav', :width => 0, :height => 0
    end

    load_avatars
    load_current_tweets
    
    animate(1) do
      if @jabber.connected? 
        @first = true
        @jabber.received_messages do |m|
          @chat_sound.play if @first && sound?
          @first = false
          if m.from == "twitter@twitter.com" && m.type == :chat
            twit(m.body, m.body[0, m.body.index(":")])
          end 
        end
      end    
    end
  end
  
end

Shoes.app :width => 400, :height => 600, :resizable => true, :title => "Twingle, experience twitter"
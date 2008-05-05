Shoes.setup do
  gem "xmpp4r-simple"
  gem "json_pure"
end

require "xmpp4r-simple"
require "yaml"
require "json/pure"

Shoes.app :width => 400, :height => 600, :resizable => true, :title => "Twingle, experience twitter" do
  
  @settings = YAML.load_file('twingle.yaml')
  @jabber = Jabber::Simple.new(@settings["jabber"]["jid"], @settings["jabber"]["password"]) 
  @count = 0
  
  def sound?
    return @settings["sound"]
  end

  def twit(what)
    @tweets.prepend {     
      flow :margin => 5 do 
        background "#191616" .. "#363636", :radius => 8
        stack :width => 58, :margin => 5 do
          background "default_profile_normal.png", :width => 48, :height => 48, :radius => 4
          image "spacer.gif", :width => 48, :height => 48
        end
        stack :width => -58, :margin => 5 do
          eval("para #{linkinizer(what)}, :stroke => '#fff', :margin => 0, :font => 'Arial 12px'")
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
    @jabber.deliver("twitter@twitter.com", @say_it.text)
    twit("You: " + @say_it.text)
    @say_it.text = ''
  end
  
  background "#000"
  flow :width => -15 do 
    @header = stack do
      background "#fff"
      flow do
        title "Twingle", :width => -110
        stack :width => 100, :right => 0, :top => 5 do
          @status = para strong("> <"), :stroke => '#F00'
        end
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
  
  animate(1) do
    if @jabber.connected? 
      @first = true
      @jabber.received_messages do |m|
        @chat_sound.play if @first && sound?
        @first = false
        if m.from == "twitter@twitter.com" && m.type == :chat
          @count += 1
          twit(m.body)
        end 
      end
      @status.replace strong(">-<(" + @count.to_s + ")"), :stroke => '#0C0'
    else
      @status.replace strong("> <"), :stroke => '#F00'
    end    
  end
  
  if sound?
    @chat_sound = video 'chat2.wav', :width => 0, :height => 0
  end
  
  
end
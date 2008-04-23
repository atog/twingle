YOUR_JID = ""
YOUR_PASSWORD = ""

Shoes.setup do
  gem "xmpp4r-simple"
end

require "xmpp4r-simple"

Shoes.app :width => 300, :height => 600, :resizable => true, :title => "Twingle, experience twitter" do
  
  def linkinizer(message)
    if /http:\/\/\S+|@\w+/i =~ message
      result = ""
      pindex = 0
      message.scan(/http:\/\/\S+|@\w+/i) do |l|
        index = message.rindex(l)
        result << "\"#{message[pindex, index-pindex]}\"," if index > 0
        result << " link(\"#{l}\", :click => "
        if /@(\S+)/ =~ l
          result << "\"http://twitter.com/#{l[/@(\w+)/,1]}\"),"
        else
          result << "\"#{l}\"),"
        end
        pindex = index + l.length
      end
      result << " \"#{$'}\""
      eval("para " + result)
    else
      para message
    end    
  end
  
  background "#eed"
  
  @jabber = Jabber::Simple.new(YOUR_JID, YOUR_PASSWORD)  
    
  @main = stack do
    background "#fff"
    title "Twingle"
  end
  
  stack :margin => 5 do
    @say_it = edit_box :margin => 5, :width => 250, :height => 50, :size => 9
    button "Say it" do
      @jabber.deliver("twitter@twitter.com", @say_it.text)
      @tweets.prepend { linkinizer("You! " + @say_it.text) }
      @say_it.text = ''
    end
  end 
    
  @tweets = stack
  
  animate(1) do
    @jabber.received_messages do |m|
      @tweets.prepend { linkinizer(m.body) if m.from == "twitter@twitter.com" && m.type == :chat }
    end    
  end
  
end
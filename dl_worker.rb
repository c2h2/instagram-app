require 'redis-queue'
require "instagram"
require "pp"
require 'open-uri'
require 'fileutils'
require "./config.rb"
require "./common.rb"


$queue = Redis::Queue.new(QUE_NAME, QUE_SUB_NMAE, :redis => Redis.new)

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.95 Safari/537.36"
DIR=`pwd`.strip+"/insta_data"
TIMEOUT=20
THREADS=100

def instagram_dl url, user, original_url, text
  fn = original_url.split("/").last + ".JPEG"
  content = ""
  open(url, "rb", 'User-Agent' => UA ) do |remote|
    content = remote.read
  end

  dir = DIR + "/" + user

  FileUtils.mkpath(dir)

  File.open(dir+"/"+fn, "wb") do |local|
    local.write(content)
  end

  File.open(dir+"/"+fn+".txt", "wb") do |local|
    local.write(text)
  end

end


def work obj
begin
 mi = Marshal.load(obj)
   instagram_dl mi.image_url, mi.user, mi.insta_url, mi.tags * "\n"
   puts "#{mi.image_url} written."
rescue Exception
 puts $!, $@
end

end



while true

  work $queue.pop

end

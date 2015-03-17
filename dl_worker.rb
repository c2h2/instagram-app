require 'redis-queue'
require "instagram"
require "pp"
require 'open-uri'
require 'fileutils'
require "./config.rb"
require "./common.rb"

#require "hashie" #try

$queue = Redis::Queue.new(QUE_NAME, QUE_SUB_NMAE, :redis => Redis.new)

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.95 Safari/537.36"
DIR=`pwd`.strip+"/insta_data"
TIMEOUT=20
THREADS=10

def instagram_dl url, user, original_url, tags, likes, media_id
  begin

    if likes < 4
      return 2
    end

    unique_id = original_url.split("/").last
    fn = media_id + ".JPEG"

    #USER DIR
    dir = DIR + "/users/" + user.split("")[0]+"/"+user

    FileUtils.mkpath(dir)
    _fn="#{dir}/#{fn}"

    if File.file?(_fn)
      return 1
    else

      content = ""
      open(url, "rb", 'User-Agent' => UA ) do |remote|
        content = remote.read
      end
    end

    File.open(_fn, "wb") do |local|
      local.write(content)
    end

    #META and TAGS
    dir = DIR + "/meta"
    FileUtils.mkpath(dir)
    _fn= "#{dir}/#{media_id}-#{user}.txt"

    File.open(_fn, "wb") do |local|
      local.write("#{fn}|#{media_id}|#{user}|#{original_url}|#{likes}|#{tags * ','}")
    end

    return 0

  rescue Exception
    puts $!, $@
    return -1
  end

end


def work obj, retry_count=3
  mi = Marshal.load(obj)
  if retry_count <= 0
    puts "TOTAL_FAILED: #{mi.user} #{mi.image_url}"
  end

  code = instagram_dl mi.image_url, mi.user, mi.insta_url, mi.tags, mi.likes, mi.media_id
  if code == 0
    puts "OKAY: #{mi.user} #{mi.image_url}"
  elsif code == 1
    puts "ALEADY have: #{mi.user} #{mi.image_url}"
  elsif code == 2
    puts "SPAM : #{mi.user} #{mi.image_url}"
  else
    puts "RETRY: #{mi.user} #{mi.image_url}"
    work obj, retry_count - 1
  end

end

puts "STARTING WITH #{THREADS} workers."

threads=[]
THREADS.times do |t|
  threads << Thread.new{
    while true

        work $queue.pop

    end
  }
end

threads.each{|t| t.join}

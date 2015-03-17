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
THREADS=32

def instagram_dl url, user, original_url, tags
  begin
    unique_id = original_url.split("/").last
    fn = unique_id + ".JPEG"

    #USER DIR
    dir = DIR + "/users/" + user

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

    #META
    dir = DIR + "/meta"
    FileUtils.mkpath(dir)
    _fn= "#{dir}/#{unique_id}-#{user}.txt"

    File.open(_fn, "wb") do |local|
      local.write(tags * "\n")
    end

    #TAGS
    tags.each do |tag|
      dir = DIR + "/tags/" + tag
      FileUtils.mkpath(dir)
      _fn="#{dir}/#{fn}"
      File.open(_fn, "wb") do |local|
        local.write(content)
      end
    end


    return 0

  rescue Exception
    puts $!, $@
    return -1
  end

end


def work obj
  mi = Marshal.load(obj)
  code = instagram_dl mi.image_url, mi.user, mi.insta_url, mi.tags
  if code == 0
    puts "OKAY: #{mi.user} #{mi.image_url}"
  elsif code == 1
    puts "ALEADY have: #{mi.user} #{mi.image_url}"
  else
    puts "FAILED: #{mi.user} #{mi.image_url}"
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

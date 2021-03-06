require "sinatra"
require "instagram"
require "pp"
require 'redis-queue'
require "./common.rb"

set :bind, '0.0.0.0'
enable :sessions

require "./config"

PER_PAGE = 50

$queue = Redis::Queue.new(QUE_NAME, QUE_SUB_NMAE, :redis => Redis.new)

get "/" do
  '<ol>
   <li><a href="/oauth/connect">Connect with Instagram</a></li>
   <li><a href="/nav">Go to Navigation</a></li>
   </ol>'
end

get "/oauth/connect" do
  redirect Instagram.authorize_url(:redirect_uri => CALLBACK_URL)
end

get "/oauth/callback" do
  response = Instagram.get_access_token(params[:code], :redirect_uri => CALLBACK_URL)
  session[:access_token] = response.access_token
  redirect "/nav"
end

get "/nav" do
  html =
  """
    <h1>Ruby Instagram Gem Sample Application</h1>
    <ol>
      <li><a href='/user/deadmau5'>User Recent Media</a> Calls user_recent_media - Get a list of a user's most recent media</li>
      <li><a href='/tags/porsche991/5'>Tags</a> Search for tags, view tag info and get media by tag</li>
      <li><a href='/user_media_feed'>User Media Feed</a> Calls user_media_feed - Get the currently authenticated user's media feed uses pagination</li>
      <li><a href='/location_recent_media'>Location Recent Media</a> Calls location_recent_media - Get a list of recent media at a given location, in this case, the Instagram office</li>
      <li><a href='/media_search'>Media Search</a> Calls media_search - Get a list of media close to a given latitude and longitude</li>
      <li><a href='/media_popular'>Popular Media</a> Calls media_popular - Get a list of the overall most popular media items</li>
      <li><a href='/user_search'>User Search</a> Calls user_search - Search for users on instagram, by name or username</li>
      <li><a href='/location_search'>Location Search</a> Calls location_search - Search for a location by lat/lng</li>
      <li><a href='/limits'>View Rate Limit and Remaining API calls</a>View remaining and ratelimit info.</li>
    </ol>
  """
  html
end

def _pre_process_resp resp
  #going to do storage stuff.
  resp.each do |media_item|
    obj = MyInsta.new
    obj.image_url =media_item.images.standard_resolution.url
    obj.insta_url = media_item.link
    obj.tags = media_item.tags
    obj.user = media_item.user.username
    obj.likes = media_item.likes[:count]
    obj.media_id=media_item.id
    $queue.push Marshal.dump(obj)
  end
  return
end

def process_resp_with_like resp
  _pre_process_resp resp

  resp.each do |r|
    $tags += r.tags
    $users += r.comments.data.map{|u| u.from.username}
  end

  #ret = resp.map{|media_item|  "<div style='float:left;'><img src='#{media_item.images.thumbnail.url}'><br/> <a href='/media_like/#{media_item.id}'>Like</a>  <a href='/media_unlike/#{media_item.id}'>Un-Like</a>  <br/>LikesCount=#{media_item.likes[:count]}</div>" } *"\n"
  ret = resp.map{|media_item|  "<div style='float:left;'><img src='#{media_item.images.thumbnail.url}'><br/><br/>Likes=#{media_item.likes[:count]}</div>" } *"\n"

end

def process_resp_thumb_only resp
  _pre_process_resp resp
  resp.map{|r| "<img src='#{r.images.thumbnail.url}'>" } * "\n"
end

def process_resp_std_with_debug resp
  _pre_process_resp resp
  resp.map{|r|  "<img src='#{r.images.standard_resolution.url}'> <pre>#{r.pretty_inspect}</pre>" } * "\n"
end

get "/user/:who" do
  `echo #{params[:who]} >> requested_users.txt`
  $tags=[]
  $users=[]
  client = Instagram.client(:access_token => session[:access_token])
  user = client.user_search(params[:who]).first
  resp = client.user_recent_media( user.id , :count=>PER_PAGE)
  html = "<h1>#{params[:who]}'s recent media</h1>"
  num_pix = 0
  temp = process_resp_with_like(resp)
  num_pix = resp.count
  num_pages = 1
  200.times do |i|
    max_id = resp.pagination.next_max_id
    if max_id.nil?
      break
    end

    num_pages +=1
    puts "Page #{num_pages}"
    resp= client.user_recent_media( user.id , {:count=>PER_PAGE, :max_id => max_id})
    num_pix += resp.count
    temp << process_resp_with_like(resp)
  end
  html << "<h2>page count = #{num_pages}, pix count = #{num_pix}</h2>"
  html << "<h3>Users: </h3>" + $users.uniq.sort.map{|user|"<a href='/user/#{user}'>#{user}</a>"} * " " + "<br>"
  html << "<h3>Tags: </h3>"  + $tags.uniq.sort.map{|tag|"<a href='/tags/#{tag}/5'>#{tag}</a>"} * " " + "<br>"
  html << temp
  html
end

get "/tags/:name/:pages" do
  `echo #{params[:name]} >> requested_tags.txt`
  $tags=[]
  $users=[]
  client = Instagram.client(:access_token => session[:access_token])
  html = "<h1>Search for tags, get tag info and get media by tag</h1>"
  tags = client.tag_search(params[:name])

  html << "<h2>Tag Name = #{tags[0].name}. Media Count =  #{tags[0].media_count}. </h2><br/><br/>"
  html << "<pre>#{tags.pretty_inspect}</pre>"

  resp=client.tag_recent_media(tags[0].name, {:count => PER_PAGE})
  html << process_resp_with_like(resp)

  (params[:pages].to_i - 1 ).times do |i|
    max_id = resp.pagination.next_max_id

    resp= client.tag_recent_media(tags[0].name, {:count => PER_PAGE, :max_tag_id => max_id})
    html << process_resp_with_like(resp)
  end

  html
end

get "/user_media_feed" do
  $tags=[]
  $users=[]
  client = Instagram.client(:access_token => session[:access_token])
  user = client.user
  html = "<h1>#{user.username}'s media feed</h1>"

  page_1 = client.user_media_feed(777)
  html << process_resp_with_like(page_1)

  page = page_1

  20.times do |i|
    max_id = page.pagination.next_max_id
    page = client.user_recent_media(777, :max_id => max_id )
    html << "<h2>Page #{i}</h2><br/>"
    html << process_resp_with_like(page)
  end

  html
end


get '/media_like/:id' do
  client = Instagram.client(:access_token => session[:access_token])
  client.like_media("#{params[:id]}")
  redirect "/user_recent_media"
end

get '/media_unlike/:id' do
  client = Instagram.client(:access_token => session[:access_token])
  client.unlike_media("#{params[:id]}")
  redirect "/user_recent_media"
end

get "/location_recent_media" do
  client = Instagram.client(:access_token => session[:access_token])
  html = "<h1>Media from the Instagram Office</h1>"
  for media_item in client.location_recent_media(514276)
    html << "<img src='#{media_item.images.thumbnail.url}'>"
  end
  html
end

get "/media_search" do
  client = Instagram.client(:access_token => session[:access_token])
  html = "<h1>Get a list of media close to a given latitude and longitude</h1>"
  for media_item in client.media_search("37.7808851","-122.3948632")
    html << "<img src='#{media_item.images.thumbnail.url}'>"
  end
  html
end

get "/media_popular" do
  client = Instagram.client(:access_token => session[:access_token])
  html = "<h1>Get a list of the overall most popular media items</h1>"
  for media_item in client.media_popular
    html << "<img src='#{media_item.images.thumbnail.url}'>"
  end
  html
end

get "/user_search" do
  client = Instagram.client(:access_token => session[:access_token])
  html = "<h1>Search for users on instagram, by name or usernames</h1>"
  for user in client.user_search("instagram")
    html << "<li> <img src='#{user.profile_picture}'> #{user.username} #{user.full_name}</li>"
  end
  html
end

get "/location_search" do
  client = Instagram.client(:access_token => session[:access_token])
  html = "<h1>Search for a location by lat/lng with a radius of 5000m</h1>"
  for location in client.location_search("48.858844","2.294351","5000")
    html << "<li> #{location.name} <a href='https://www.google.com/maps/preview/@#{location.latitude},#{location.longitude},19z'>Map</a></li>"
  end
  html
end


get "/limits" do
  client = Instagram.client(:access_token => session[:access_token])
  html = "<h1/>View API Rate Limit and calls remaining</h1>"
  response = client.utils_raw_response
  html << "Rate Limit = #{response.headers[:x_ratelimit_limit]}.  <br/>Calls Remaining = #{response.headers[:x_ratelimit_remaining]}"

  html
end

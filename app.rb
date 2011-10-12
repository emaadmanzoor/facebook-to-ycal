require "sinatra"
require "mogli"
require "uri"
require "net/http"
require "digest"

enable :sessions
set :raise_errors, false
set :show_exceptions, false

# Scope defines what permissions that we are asking the user to grant.
# In this example, we are asking for the ability to publish stories
# about using the app, access to what the user likes, and to be able
# to use their pictures.  You should rewrite this scope with whatever
# permissions your app needs.
# See https://developers.facebook.com/docs/reference/api/permissions/
# for a full list of permissions
FACEBOOK_SCOPE = 'user_likes,user_photos,user_photo_video_tags,friends_birthday,user_birthday'

unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

helpers do
  def url(path)
    base = "#{request.scheme}://#{request.env['HTTP_HOST']}"
    base + path
  end

  def post_to_wall_url
    "https://www.facebook.com/dialog/feed?redirect_uri=#{url("/close")}&display=popup&app_id=#{@app.id}";
  end

  def send_to_friends_url
    "https://www.facebook.com/dialog/send?redirect_uri=#{url("/close")}&display=popup&app_id=#{@app.id}&link=#{url('/')}";
  end

  def authenticator
    @authenticator ||= Mogli::Authenticator.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], url("/auth/facebook/callback"))
  end

  def first_column(item, collection)
    return ' class="first-column"' if collection.index(item)%4 == 0
  end

  def print_birthdays
    @requests = []
    @birthdays = @client.fql_query("select name,birthday_date from user where uid in (select uid2 from friend where uid1=me())")
    @birthdays.each do |friend|
      name = friend["name"].to_s
      title = URI.escape(name + ": Birthday")
      desc = URI.escape("Added by fb2ycal")
      birthday = "2011" + friend["birthday_date"].to_s.split('/').join('')[0..3]
      start_time = birthday + "T" + "000000"
      end_time = birthday + "T" + "235959"
      query = "http://qa.calendar.yahoo.com/ae?TITLE=" + title + "&DESC=" + desc + "&ST=" + start_time + "&ET=" + end_time + "&RPAT=01yr&REM1=12h&REM2=2h"
      @requests.push(query)
    end
    return @requests.to_s
  end
end

# the facebook session expired! reset ours and restart the process
error(Mogli::Client::HTTPException) do
  session[:at] = nil
  redirect "/auth/facebook"
end

get "/" do
  redirect "/auth/facebook" unless session[:at]
  @client = Mogli::Client.new(session[:at])

  # limit queries to 15 results
  @client.default_params[:limit] = 15

  @app  = Mogli::Application.find(ENV["FACEBOOK_APP_ID"], @client)
  @user = Mogli::User.find("me", @client)

  # access friends, photos and likes directly through the user instance
  @friends = @user.friends[0, 4]
  @photos  = @user.photos[0, 16]
  @likes   = @user.likes[0, 4]

  # for other data you can always run fql
  @friends_using_app = @client.fql_query("SELECT uid, name, is_app_user, pic_square FROM user WHERE uid in (SELECT uid2 FROM friend WHERE uid1 = me()) AND is_app_user = 1")

  erb :index
end

# used to close the browser window opened to post to wall/send to friends
get "/close" do
  "<body onload='window.close();'/>"
end

get "/auth/facebook" do
  session[:at]=nil
  redirect authenticator.authorize_url(:scope => FACEBOOK_SCOPE, :display => 'page')
end

get '/auth/facebook/callback' do
  client = Mogli::Client.create_from_code_and_authenticator(params[:code], authenticator)
  session[:at] = client.access_token
  redirect '/'
end

post '/add' do
  #redirect "/auth/yahoo" unless session[:y]
  url = URI.parse("http://qa.calendar.yahoo.com/ae?TITLE=Rijul%20Jain%27s%20Birthday&DESC=Added%20by%20fb2ycal&ST=20110420T000000&ET=20110420T235959&RPAT=01yr&REM1=12h&REM2=2h")
  http = Net::HTTP.new(url.host, url.port)
  headers = {
    "Cookie" => "B=8aiiv4h79a9lt&b=4&d=2Qzmc7xpYF6sXdm3TW2wVkYhNfM-&s=4c&i=ooV.HzxluLfXFwEJhyDc; F=a=WNjVKaoMvTY0W41r1dZTRGrHSd1twT62pdy9Kurskn.U1XYSAs6UDnlqnipe0EdLvzhpxSM-&b=N8og; Y=v=1&n=2vdu8c2g31epv&l=4c003c0dpeeh/o&p=m2qvvin012000000&iz=&r=nf&lg=en-IN&intl=in&np=1; PH=fn=nXVoYla.TDJw7guUnmA-&l=en-IN&d=49e.gwlwlY9jwDlkbkyyHKT5oA--&s=6j; T=z=JbSlOBJv5pOBGqFTdfD4n.xTjMwBjZPNzYzMzc0NjJPNDZPTz&a=QAE&sk=DAAKus7xfXfvbm&ks=EAAfRhESIkzGDrvG981mraGZw--~E&d=c2wBT1RRM0FURTRNREUwTkRBek1UVTRNekU0T0RFdwFhAVFBRQFnAUNFVFczWk03RldMUVFYSUgyTUNPT0o1RjJVAXRpcAFMUEYua0EBenoBSmJTbE9CQTdF; BA=ba=3717&ip=203.83.248.36&t=1318402925; YC.ZP_emaadmanzoor=mvh_height=51&mvheight=463"
  }
  http.get(url.path, headers)
end

get "/auth/yahoo" do
  session[:y]=nil
  appid="hZ9Qoq_IkY07N_WJ.pvaz.gOaxtt7Vt3EsDb6A--"
  time = Time.now.to_i
  secret = "3462eda3e46bf2bc7d6e3289877ad39c"
  sig = Digest::MD5.hexdigest("/WSLogin/V1/wslogin?appid=" + appid + "&ts=" + time.to_s + secret)
  url = "https://api.login.yahoo.com/WSLogin/V1/wslogin?appid=" + appid + "&ts=" + time.to_s + "&sig=" + sig
  redirect url
end

get "/yahoo_success/?" do
  session[:y] = params[:token]
  appid="hZ9Qoq_IkY07N_WJ.pvaz.gOaxtt7Vt3EsDb6A--"
  time = Time.now.to_i
  secret = "3462eda3e46bf2bc7d6e3289877ad39c"
  sig = Digest::MD5.hexdigest("/WSLogin/V1/wspwtoken_login?appid=" + appid + "&token" + session[:y] + "&ts=" + time.to_s + secret)
  url = "https://api.login.yahoo.com/WSLogin/V1/wspwtoken_login?appid=" + appid + "&token" + session[:y] + "&ts=" + time.to_s + "&sig=" + sig
   
end

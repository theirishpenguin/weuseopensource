require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-types'
require 'dm-validations'
require 'dm-timestamps'
require 'uuidtools'
require 'rack-flash'
#require 'ruby-debug'

#enable :methodoverride
enable :sessions
use Rack::Flash


# Define a method called send_confirmation email to send email your own prefered way
# in a file called emailconfig.rb file in the current directory and set MAILER_ENABLED
# to true. Otherwise, this require statement should be commented out
require 'emailconfig'

MAILER_ENABLED = true # Set this to true if you have a valid mail configuration in emailconfig.rb
DOMAIN = 'localhost:4567'

module UuidHelper
  def generate_uuid
    self.uuid = UUID.timestamp_create().to_s
  end
end


DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/openlove.sqlite3")

class Company
  include DataMapper::Resource, UuidHelper
  before :create, :generate_uuid


  property :id, Integer, :serial => true    # primary serial key
  property :website, String, :nullable => false, :unique => true, :length => (1..100)
  property :company_email, String, :nullable => false, :format => :email_address, :unique => true
  property :admin_email, String, :nullable => false, :format => :email_address, :unique => true
  property :name, String, :nullable => false
  property :blurb, String, :nullable => false
  property :description, Text
  property :created_at, DateTime
  property :updated_at, DateTime
  property :uuid, String #OPTIMIZEME: When db platform decided
  property :status, Enum[:pending, :notified, :activated, :suspended], :nullable => false

  validates_with_method :admin_email, :method => :check_email_consistency_wrt_website

  def check_email_consistency_wrt_website #TODO: Unit test me!
    consistency = [false, "The domain of the Admin Email and Company Website much match"]

    email_domain = admin_email.split('@')[1]

    unless email_domain.blank? or website.blank?
      website_domain = website
      website_domain = website[4, website.length] if website.start_with? 'www.'

      consistency = true if email_domain == website_domain
    end

    consistency
  end
end


DataMapper.auto_upgrade!



get '/' do
  @companies = Company.all
  erb :index
end

get '/new' do
  @company = Company.new
  erb :new
end

post '/create' do

  @company = Company.new(
    :website => params[:company_website],
    :name => params[:company_name],
    :blurb => params[:company_blurb],
    :description => params[:company_description],
    :company_email => params[:company_email],
    :admin_email => params[:admin_email],
    :status => :pending)

  if @company.save
    # TODO
    if MAILER_ENABLED 
      send_confirmation_email('no-reply@example.com', @company.admin_email, 'You need to activate your account',
      "Please click this link or copy and paste it into your browser http://localhost:4567/update/#{@company.uuid}")
      @company.update_attributes(:status => :notified)
    end

    redirect '/'
  else
    flash.now[:notice] = @company.errors
    erb :new
  end
end

get '/edit/:uuid' do
  @company = Company.first(:uuid => params[:uuid])
  erb :edit
end

# TODO: Is there a way to carry out activation without doing a get call
# or at least using the _method=POST hack somehow?
get '/update/:uuid' do
  @company = Company.first(:uuid => params[:uuid])

  if @company.nil? #FIXME
    raise 'No such account. Please contact our support team.'
  end

  if @company.status == :notified
    @company.update_attributes(:status => :activated)

    @admin_link = "http://#{DOMAIN}/edit/#{@company.uuid}"

    if MAILER_ENABLED 
      send_confirmation_email('no-reply@example.com', @company.admin_email, 'Account Activated',
      "Please click this link or copy and paste it into your browser #{@admin_link} to make changes to your account.")
    end

    erb :welcome
  else
    # TODO: Move this out of here eventually
    raise 'Your account is not currently active. Please contact our support team.'
  end
end

post '/update/:uuid' do
  @company = Company.first(:uuid => params[:uuid])

# TODO: Commented out until we see if we can do an POST account activation
#  # First time, this is called activate account
#  if @company.status == :notified
#    @company.update_attributes(:status => :activated)
#
#    erb :welcome
#
#  elsif @company.status == :activated
    if @company.status == :activated

    @company.update_attributes(
      :website => params[:company_website],
      :blurb => params[:company_blurb],
      :name => params[:company_name],
      :description => params[:company_description],
      :company_email => params[:company_email],
      :admin_email => params[:admin_email])

    if @company.save
      redirect '/'
    else
      erb :new
    end

  else
    # TODO: Move this out of here eventually
    raise 'Your account is not currently active. Please contact our support team.'
  end

end

private

# TODO: Move to helpers file
def format_errors(errors)
  msg = ''
  @company.errors.each_pair {|k,v| msg << "<li>#{v * '</li><li>'}</li>"}
  msg = "Please fix the following errors:<br /><ul>#{msg}</ul>" unless msg.empty?
  msg
end

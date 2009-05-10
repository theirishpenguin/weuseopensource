require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-types'
require 'dm-validations'
require 'dm-timestamps'
require 'uuidtools'
require 'rack-flash'
require 'ruby-debug'

enable :methodoverride
enable :sessions
use Rack::Flash


# Define a method called send_confirmation email to send email your own prefered way
# in a file called emailconfig.rb file in the current directory and set MAILER_ENABLED
# to true. Otherwise, this require statement should be commented out
require 'emailconfig'

MAILER_ENABLED = true # Set this to true if you have a valid mail configuration in emailconfig.rb
DOMAIN = 'localhost:4567'
load 'industry_list.rb' # Pulls in a list of industries simply defines @@industry_list

@@usage_level_list = [
  {'1' => 'Use'},
  {'2' => 'Develop'},
  {'3' => 'Sell'}].freeze

module UuidHelper
  def generate_uuid
    self.uuid = UUID.timestamp_create().to_s
  end
end


DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/openlove.sqlite3")

class Company
  include DataMapper::Resource, UuidHelper
  before :create, :generate_uuid


  property :id, Integer, :serial => true
  property :website, String, :unique => true, :length => (1..100)
  property :business_category, Integer, :nullable => false
  property :usage_level, Integer, :nullable => false
  property :company_email, String, :nullable => false, :format => :email_address, :unique => true
  property :admin_email, String, :nullable => false, :format => :email_address, :unique => true
  property :name, String, :unique => true, :length => (1..60)
  property :blurb, String, :length => (1..300)
  property :description, Text, :length => (1..2000)
  property :created_at, DateTime
  property :updated_at, DateTime
  property :uuid, String #OPTIMIZEME: When db platform decided optimize type used for storage
  property :status, Enum[:pending, :notified, :activated, :suspended], :nullable => false

  validates_with_method :admin_email, :method => :check_email_consistency_wrt_website
  validates_with_method :blurb, :method => :blurb_legal_character_check
  validates_with_method :description, :method => :description_legal_character_check

  private
  def blurb_legal_character_check; legal_character_check('Blurb', blurb); end
  def description_legal_character_check; legal_character_check('Description', description); end

  def legal_character_check(field, val)
    success = [false, "#{field} cannot contain newlines or tabs"]
    success = true if (/[\r\n\t]/.match val).nil?
    success
  end

  def check_email_consistency_wrt_website
    consistency = [false, "The domain of the Admin Email and Company Website must match"]

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



### ACTIVATION RESOURCE ###

get '/activation/:uuid/new' do
  @company = Company.first(:uuid => params[:uuid])

  if @company.status == :notified
    erb :'activation/activate'
  elsif @company.status == :activated # TODO: Change from exception
    raise 'Your account is already active.'
  else #TODO: Change from exception
    raise 'Your account cannot be activated.'
  end

end

post '/activation/:uuid' do
  @company = Company.first(:uuid => params[:uuid])

  if @company.status == :notified
    @company.update_attributes(:status => :activated)
    @admin_link = "http://#{DOMAIN}/companies/#{@company.uuid}/edit"

    if MAILER_ENABLED 
      send_confirmation_email('no-reply@example.com', @company.admin_email, 'Account Activated',
      "Please click this link or copy and paste it into your browser #{@admin_link} to make changes to your account.")
    end

    erb :'activation/welcome'
  elsif @company.status == :activated # TODO: Change from exception
    raise 'Your account is already active.'
  else #TODO: Change from exception
    raise 'Your account cannot be activated.'
  end
end

### ### ### ### ### ###





### company_summaries ###

get '/company_summaries/:name' do
    @company = Company.first(:name => params[:name])
    erb(:'company_summaries/show', :layout => false)
end

### ### ### ### ### ###





### weuseopensource ###

get '/' do
  @companies = Company.all
  erb :index
end

get '/companies/new' do
  @company = Company.new
  @industry_list = @@industry_list
  @usage_level_list = @@usage_level_list
  erb :new
end

post '/companies' do
  @industry_list = @@industry_list
  @usage_level_list = @@usage_level_list

  @company = Company.new(
    :business_category => params[:company_business_category],
    :usage_level => params[:company_usage_level],
    :website => params[:company_website],
    :name => params[:company_name],
    :blurb => params[:company_blurb],
    :description => params[:company_description],
    :company_email => params[:company_email],
    :admin_email => params[:admin_email],
    :status => :pending)

  if @company.save

    if MAILER_ENABLED 
      send_confirmation_email('no-reply@example.com', @company.admin_email, 'You need to activate your account',
      "Please click this link or copy and paste it into your browser http://#{DOMAIN}/activation/#{@company.uuid}/new")
      @company.update_attributes(:status => :notified)
    end

    redirect '/'
  else
    flash.now[:notice] = @company.errors
    erb :new
  end
end

get '/companies/:uuid/edit' do
  @industry_list = @@industry_list
  @usage_level_list = @@usage_level_list

  @company = Company.first(:uuid => params[:uuid])
  raise 'No such account.' if @company.nil?
  erb :edit
end

put '/companies/:uuid' do
  @industry_list = @@industry_list
  @usage_level_list = @@usage_level_list

  @company = Company.first(:uuid => params[:uuid])

  if @company.status == :activated

    if @company.update_attributes(
      :business_category => params[:company_business_category],
      :usage_level => params[:company_usage_level],
      :website => params[:company_website],
      :blurb => params[:company_blurb],
      :name => params[:company_name],
      :description => params[:company_description],
      :company_email => params[:company_email],
      :admin_email => params[:admin_email])

      redirect '/'
    else
      erb :edit
    end

  else #TODO: Change from exception
    raise 'Your account is not currently active. Please contact our support team.'
  end

end

### ### ### ### ### ###


private

### HELPERS ###

helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def format_errors(errors)
    msg = ''
    @company.errors.each_pair {|k,v| msg << "<li>#{v * '</li><li>'}</li>"}
    msg = "Please fix the following errors:<br /><ul>#{msg}</ul>" unless msg.empty?
    msg
  end

  # Basic implementation of a HTML SELECT helper
  def select(resource_name, field_name, options_list, selected_value)
    html = ''
    options_list.each do |nv_pair|
      option_value = nv_pair.keys.first
      option_name = nv_pair.values.first
      html << "<option value=\"#{option_value}\""
      html << " selected=\"true\"" if option_value == selected_value
      html << '>'
      html << option_name
      html << "</option>"
    end
    "<select name=\"#{resource_name}_#{field_name}\">#{html}</select>"
  end

end

### ### ### ### ### ###

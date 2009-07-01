require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-types'
require 'dm-validations'
require 'dm-timestamps'
require 'uuidtools'
require 'rack-flash'
#require 'ruby-debug'

enable :methodoverride
enable :sessions
use Rack::Flash


# Define a method called send_confirmation email to send email your own prefered way
# in a file called emailconfig.rb file in the current directory and set MAILER_ENABLED
# to true. Otherwise, this require statement should be commented out
#require 'emailconfig'

MAILER_ENABLED = false # Set this to true if you have a valid mail configuration in emailconfig.rb
DOMAIN = 'localhost:4567'
load 'industry_list.rb' # Pulls in a list of industries simply defines @@industry_list

# List of domains that cannot signup without extra verifying of their authenticity
require 'suspicious_domains'

@@usage_level_list = [
  {'1' => 'Use'},
  {'2' => 'Develop'},
  {'3' => 'Sell'}].freeze

def get_max_id(list)
    list.inject(0) do |memo,keys|
        current = keys.first.first.to_i
        current > memo ? current : memo
    end
end

@@max_business_category_id ||= get_max_id(@@industry_list)
@@max_usage_level_id ||= get_max_id(@@usage_level_list)

module UuidHelper
  def generate_unique_identifiers
    #needs to start with a letter for use in javascript ids(w3c validation)
    self.handle = "p_#{UUID.timestamp_create()}"
    self.uuid = UUID.timestamp_create().to_s
  end
end


DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/openlove.sqlite3")

class Company
  include DataMapper::Resource, UuidHelper
  before :create, :generate_unique_identifiers


  property :handle, String #OPTIMIZEME: When db platform decided optimize type used for storage
  property :id, Integer, :serial => true
  property :website, String, :unique => true, :length => (1..100)
  property :business_category_id, Integer
  property :usage_level_id, Integer
  property :company_email, String, :nullable => false, :format => :email_address, :unique => true
  property :admin_email, String, :nullable => false, :format => :email_address, :unique => true
  property :company_telephone, String, :length => (0..60)
  property :company_address1, String, :length => (0..60)
  property :company_address2, String, :length => (0..60)   
  property :company_address3, String, :length => (0..60)
  property :name, String, :unique => true, :length => (1..60)
  property :blurb, String, :length => (1..300)
  property :description, Text, :length => (0..2000)
  property :created_at, DateTime
  property :updated_at, DateTime
  property :activated_at, DateTime, :default => nil
  property :uuid, String #OPTIMIZEME: When db platform decided optimize type used for storage
  property :status, Enum[:pending, :notified, :activated, :suspended], :nullable => false

  validates_within :business_category_id, :set => (1..@@max_business_category_id),
	  :message => 'Please select an Industry Type' # Implicitly cannot be blank
  validates_within :usage_level_id, :set => (1..@@max_usage_level_id),
	  :message => 'Please select a Usage Level' # Implicitly cannot be blank
  validates_with_method :admin_email, :method => :check_email_consistency_wrt_website
  validates_with_method :blurb, :method => :blurb_legal_character_check
  validates_with_method :description, :method => :description_legal_character_check
  validates_with_method :domain, :method => :suspicious_domain_check

  def business_category_text; @@industry_list[business_category_id].values.first; end
  def usage_level_text; @@usage_level_list[usage_level_id - 1].values.first; end # -1 because index always 1 greater than value

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
      consistency = true if email_domain == website
    end

    consistency
  end

  def suspicious_domain_check
    result = true

    @@suspicious_domain_list.each do |sus_domain|
       if website.match(sus_domain)
         result = [false, 
           "As you're a star company, we'd like to take an extra step to verify your authenticity. Please email webmaster@#{DOMAIN} to sign up instead of this form."]
       end
    end

    result
  end
end


DataMapper.auto_upgrade!



### ACTIVATION RESOURCE ###

get '/activation/:uuid/new' do
  @company = Company.first(:uuid => params[:uuid])

  if @company.status == :notified
    erb :'activation/activate'
  elsif @company.status == :activated
    redirect "/companies/#{params[:uuid]}/edit"
  else #TODO: Change from exception
    raise 'Your account cannot be activated.'
  end

end

post '/activation/:uuid' do
  @company = Company.first(:uuid => params[:uuid])

  if @company.status == :notified
    if @company.update_attributes(:status => :activated, :activated_at => DateTime.now)

      @admin_link = "http://#{DOMAIN}/companies/#{@company.uuid}/edit"

      if MAILER_ENABLED 
        send_confirmation_email('no-reply@example.com', @company.admin_email, 'Account Activated',
        "Please click this link or copy and paste it into your browser #{@admin_link} to make changes to your account.")
      end

      erb :'activation/welcome'
    else #TODO: Change from exception
      raise 'Your account cannot be activated.'
    end
  elsif @company.status == :activated # TODO: Change from exception
    raise 'Your account is already active.'
  else #TODO: Change from exception
    raise 'Your account cannot be activated.'
  end
end

### ### ### ### ### ###





### company_summaries ###

get '/company_summaries/:handle' do
    @company = Company.first(:handle => params[:handle])
    erb(:'company_summaries/show', :layout => false)
end

### ### ### ### ### ###





### weuseopensource ###

get '/' do
  @companies = Company.all
  erb :index
end

get '/filtered_companies/*' do

    # Note that the splat parameter (*) comes in as an array

    stripped_search_string = params[:splat].first.strip 

    if stripped_search_string.empty?
        @companies =  Company.all
    else
        terms = stripped_search_string.split(' ')

        # build query part of the conditions
        conditions = [Array.new(terms.length, 'name LIKE ?').join(' OR ')]
    
        # add in query parameters
        terms.each{|term| conditions << "%#{term}%"}

        @companies =  Company.all(:conditions => conditions)    
    end

    erb(:'filtered_companies/index', :layout => false)
end


get '/companies/new' do
  @company = Company.new
  @industry_list = @@industry_list
  @usage_level_list = @@usage_level_list
  erb :new
end


get '/companies/:handle' do
  @company = Company.first(:handle => params[:handle])
  erb :show
end


post '/companies' do
  @industry_list = @@industry_list
  @usage_level_list = @@usage_level_list

  @company = Company.new(
    :business_category_id => params[:company_business_category_id],
    :usage_level_id => params[:company_usage_level_id],
    :website => params[:company_website],
    :name => params[:company_name],
    :blurb => params[:company_blurb],
    :description => params[:company_description],
    :company_email => params[:company_email],
    :company_telephone => params[:company_telephone],
    :company_address1 => params[:company_address1],
    :company_address2 => params[:company_address2],
    :company_address3 => params[:company_address3],
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
      :business_category_id => params[:company_business_category_id],
      :usage_level_id => params[:company_usage_level_id],
      :website => params[:company_website],
      :blurb => params[:company_blurb],
      :name => params[:company_name],
      :description => params[:company_description],
      :company_email => params[:company_email],
      :company_telephone => params[:company_telephone],
      :company_address1 => params[:company_address1],
      :company_address2 => params[:company_address2],
      :company_address3 => params[:company_address3],
      :admin_email => params[:admin_email])

      redirect '/'
    else
      flash.now[:notice] = @company.errors
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
      html << " selected=\"selected\"" if option_value == selected_value
      html << '>'
      html << option_name
      html << "</option>"
    end
    "<select id=\"#{resource_name}_#{field_name}\" name=\"#{resource_name}_#{field_name}\" class=\"required\">#{html}</select>"
  end

  def image_for_usage_level(usage_level_id)
    case usage_level_id
    when 1: filename = 'badgeU.png'; title='User'
    when 2: filename = 'badgeD.png'; title='Developer'
    when 3: filename = 'badgeS.png'; title='Seller'
    end

    %{<img class="title" src="images/#{filename}" alt = "#{title}" title="Open Source #{title}" width="27px" height="28px" />}
  end

end

### ### ### ### ### ###

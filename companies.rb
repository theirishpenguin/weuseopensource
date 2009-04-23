require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-validations'
require 'dm-timestamps'
require 'uuidtools'

# Define a method called send_confirmation email to send email your own preffered way
# in a file called emailconfig.rb file in the current directory and set MAILER_ENABLED
# to true. Otherwise, this require statement should be commented out
# require 'emailconfig'

MAILER_ENABLED = false # Set this to true if you have a valid mail configuration in emailconfig.rb

module UuidHelper
  def generate_uuid
    self.uuid = UUID.timestamp_create().to_s
  end
end


DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/openlove.sqlite3")

class Company
  include DataMapper::Resource, UuidHelper
  before :create, :generate_uuid


  property :id,         Integer, :serial => true    # primary serial key
  property :website,    String
  property :email,      String
  property :name,       String,  :nullable => false # cannot be null
  property :description,Text
  property :created_at, DateTime
  property :updated_at, DateTime
  property :uuid,        String #OPTIMIZEME: When db platform decided

end

DataMapper.auto_upgrade!

get '/' do
  @companies = Company.all
  erb :index
end

get '/new' do
  erb :new
end

post '/create' do
  @company = Company.new(
    :website => params[:company_website],
    :name => params[:company_name],
    :description => params[:company_description],
    :email => params[:company_email])

  if @company.save
    # TODO
    #send_confirmation_email('todo', 'todo', 'todo', 'todo') if MAILER_ENABLED 
	
    redirect '/'
  else
    render '/new'
  end
end

get '/edit/:uuid' do
  @company = Company.first(:uuid => params[:uuid])
  erb :edit
end

post '/update' do
  @company = Company.new(
    :website => params[:company_website],
    :name => params[:company_name],
    :description => params[:company_description],
    :email => params[:company_email])

  if @company.save
    redirect '/'
  else
    render '/new'
  end
end

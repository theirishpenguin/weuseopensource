require 'rubygems'
require 'sinatra'
require 'dm-core'
require 'dm-validations'
require 'dm-timestamps'

DataMapper.setup(:default, "sqlite3://#{Dir.pwd}/openlove.sqlite3")

class Company
  include DataMapper::Resource

  property :id,         Integer, :serial => true    # primary serial key
  property :website,    String
  property :name,       String,  :nullable => false # cannot be null
  property :description,Text
  property :created_at, DateTime
  property :updated_at, DateTime
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
  @company = Company.new(:website => params[:company_website], :name => params[:company_name], :description => params[:company_description])
  if @company.save
    redirect '/'
  else
    render '/new'
  end
end

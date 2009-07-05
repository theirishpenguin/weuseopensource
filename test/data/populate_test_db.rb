#!/usr/bin/env ruby

$LOAD_PATH << '../../'

require 'companies'

Company.all.destroy!

(1..31).each do |i|
  company = Company.new(
	:business_category_id => 1,
	:usage_level_id => 1,
	:website => "example#{i}.com",
	:name => "example company #{i}",
	:blurb => "This is the blurb of example company #{i}",
	:description => "This is the description of example company #{i}",
	:company_email => "somebody@example#{i}.com",
	:company_telephone => '086-876456875',
	:company_address1 => 'First St',
	:company_address2 => 'First Lane',
	:company_address3 => 'Ireland',
	:admin_email => "admin@example#{i}.com",
	:status => :activated,
	:activated_at => DateTime.now)

    unless company.save
	  puts "Error saving company #{i}: #{company.errors.inspect}"
    end
end

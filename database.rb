#gem install dbi
#gem install dbd-jdbc
#gem install jdbc-sqlite3
#require 'jdbc-sqlite3'

require 'sequel'


db = Sequel.connect(
    'jdbc:sqlite:ZbojeiJureq.db') # need to set the driver

uo = db[:uprawnienia_opis]

puts uo.count

#puts uo.map { |row| "Position: #{row[:nazwa]}, #{row[:poziom]}"}

puts db[:uzytkownik].where{:dopasowanie == 0 && :nick == 'cock'}.all

puts db[:uzytkownik].where(:dopasowanie => 2).join(:uprawnienia_opis, :id => :uprawnienie).reverse_order(:poziom).select { |row|
  !(Regexp.new(row[:adres].to_s) =~ 'kaiks@dynamic-78-8-154-64.ssp.dialog.net.pl').nil? }.first

r = db[:uzytkownik].where(:dopasowanie => 2).join(:uprawnienia_opis, :id => :uprawnienie).reverse_order(:poziom).first[:adres]

puts r

puts (Regexp.new(r) =~ 'kaiks@dynamic-78-8-154-64.ssp.dialog.net.pl')

r = Regexp.new(r)

puts db[:uzytkownik].where(:dopasowanie => 2).join(:uprawnienia_opis, :id => :uprawnienie).reverse_order(:poziom).all.select{ |row|
  '~kaiks@dynamic-78-8-154-64.ssp.dialog.net.pl'.scan(Regexp.new(row[:adres].to_s)).size == 1}

puts 'aaa'

puts db[:uzytkownik].all.map{ |row| [row[:ID], '~kaiks@dynamic-78-8-154-64.ssp.dialog.net.pl'.scan(Regexp.new(row[:adres].to_s)).size ] }
#!/usr/bin/env ruby1.9.1

require 'rumpy'
require 'rubygems'
require 'tzinfo'

class Time
  def change(hash)
    arr = []
    hash.each do |h|
      case h[0]
      when :year
        arr[5] = h[1]
      when :month
        arr[4] = h[1]
      when :day
        arr[3] = h[1]
      when :hour
        arr[2] = h[1]
      when :minute
        arr[1] = h[1]
      end
    end
    self.class.new *arr
  end
end

class Noty
  include Rumpy::Bot

  def initialize
    @config_path = 'config'
    @models_path = File.dirname(__FILE__) + '/models/*.rb'
    @main_model  = :user
  end

  def parser_func(m)
    m.strip!
    m = m.split(' ', 2)
    cmd = m[0]
    opt = m[1]
    if opt.nil?
      opt = ''
    else
      opt.strip!
    end
    case cmd.downcase
    when 'help'
      {:action => :show_help, :topic => opt}
    when 'tz'
      if opt.empty?
        {:action => :show_tz}
      else
        {:action => :set_tz, :tz => opt}
      end
    when 'del'
      {:action => :delete_record, :record => opt}
    when 'list'
      {:action => :show_records}
    else
      m = /^((((?<year>\d{4}|\d{2})-)?(?<month>\d{1,2})-(?<day>\d{1,2}))|((?<day2>\d{1,2})\.(?<month2>\d{1,2})(\.(?<year2>\d{2}|\d{4}))?)|((?<mdnum>\d*)\s*(?<mdset>d|w)))?\s*(((?<hour>\d{1,2})((:(?<minute>\d{1,2}))\s*((?<hourset>a|p)\.?m\.?)|(:(?<minute2>\d{1,2}))|((?<hourset2>a|p)\.?m\.?)))|(((?<hourdel>\d*)h)?\s*((?<minutedel>\d*)m)?))$/.match cmd
      if m.nil?
        {:action => nil}
      else
        begin
#           result = Hash.new
#           m.names.each do |name|
#             result[name] = m[name]
#           end
#           return result
          parsed_dt = Time.now
          current_dt = Time.now
          if not m[:day].nil?
            #2000-10-10
            year = m[:year]
            year = current_dt.year if year.nil?
            month, day = m[:month], m[:day]
          elsif not m[:day2].nil?
            #10.10.2000
            year = m[:year2]
            year = current_dt.year if year.nil?
            month, day = m[:month2], m[:day2]
          end
          year, month, day = year.to_i, month.to_i, day.to_i if not year.nil?
          if not year.nil?
            #2000-10-10, 10.10.2000
            year = 2000+year if year < 100
            parsed_dt = parsed_dt.change :year => year, :month => month, :day => day
            parsed_dt = parsed_dt.change :year => (year+1) if parsed_dt < current_dt and m[:year].nil? and m[:year2].nil?
          elsif not m[:mdset].nil?
            #3 day, 3 week
            n = if m[:mdnum].empty?
                  1
                else 
                  m[:mdnum].to_i
                end
            n *= 7 if m[:mdset] == 'w' #weeks
            n *= 3600*24 #FIXME!!!
            parsed_dt += n
          end
#           if not m[:hour].nil?
#             #12:15, 12p.m.
#             if m[:minute] or m[:minute2] or m[:hourset2]
#               hour = m[:hour]
#               hourset = m[:hourset] if m[:hourset]
#               hourset = m[:hourset2] unless hourset
#               hour = 0 if hour == 12 and hourset == 'a'
#               puts 'WRONG DATE' if hour > 12 and hourset == 'p' #FIXME
#               hour += 12 if hour != 12 and hourset == 'p'
#               minute = if m[:minute]
#                       m[:minute].to_i
#                     elsif m[:minute2]
#                       m[:minute2].to_i
#                     else
#                       0
#                     end
#               parsed_dt.change :hour => hour
#               parsed_dt.change :minute => minute
#               parsed_dt += 3600*24 if parsed_dt < current_dt and m[:day].nil? and m[:day2].nil? and m[:mdset].nil? #FIXME
#             end
#           elsif m[:hourdel] or m[:minutedel]
#             n = 0
#             n += if m[:hourdel].empty?
#                   3600
#                 else
#                   m[:hourdel]*3600
#                 end
#             n += if m[:minutedel].empty?
#                   60
#                 else
#                   m[:minutedel]*60
#                 end
#             parsed_dt += n #FIXME
#           end
          {:action => :add_record, :time => parsed_dt, :msg => opt}
        rescue
          {:action => :shit}
        end
      end
    end
  end

  def backend_func
  end

  def do_func(model, params)
    params.to_s
  end
end

case ARGV[0]
when '--start'
  Rumpy.start Noty
when '--stop'
  Rumpy.stop Noty
end

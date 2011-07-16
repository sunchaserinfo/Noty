#!/usr/bin/env ruby1.9.1

require 'rumpy'
require 'rubygems'
require 'tzinfo'

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
    opt.strip!
    case m.downcase
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
      m = /^((((?<year>\d{4}|\d{2})-)?(?<month>\d{1,2})-(?<day>\d{1,2}))|((?<day2>\d{1,2})\.(?<month2>\d{1,2})(\.(?<year2>\d{2}|\d{4}))?)|((?<mdnum>\d*)\s*(?<mdset>d|w)))?\s*(((?<hour>\d{1,2})((:(?<mins>\d{1,2}))\s*((?<hourset>a|p)\.?m\.?)|(:(?<mins2>\d{1,2}))|((?<hourset2>a|p)\.?m\.?)))|(((?<hourdel>\d*)h)?\s*((?<minsdel>\d*)m)?))$/.match cmd
      if m.nil?
        {:action => 'none'}
      else
        parsed_dt = Time.now
        current_dt = Time.now
        year = 0
        if m[:day]
          #2000-10-10
          year = m[:year]
          year = current_dt.year if year.nil?
          month, day = m[:month], m[:day]
        elsif m[:day2]
          #10.10.2000
          year = m[:year2]
          year = current_dt.year if year.nil?
          month, day = m[:month2], m[:day2]
        end
        if not year.nil?
          #2000-10-10, 10.10.2000
          year = 2000+year if year < 1000
          parsed_dt.change :year => year
          parsed_dt.change :month => month
          parsed_dt.change :day => day
          parsed_dt.change :year => (year+1) if parsed_dt < current_dt and m[:year].nil? and m[:year2].nil?
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
        if not m[:hour].nil?
          #12:15, 12p.m.
          if m[:mins] or m[:mins2] or m[:hourset2]
            hour = m[:hour]
            hourset = m[:hourset] if m[:hourset]
            hourset = m[:hourset2] unless hourset
            hour = 0 if hour == 12 and hourset == 'a'
            puts 'WRONG DATE' if hour > 12 and hourset == 'p' #FIXME
            hour += 12 if hour != 12 and hourset == 'p'
            mins = if m[:mins]
                     m[:mins].to_i
                   elsif m[:mins2]
                     m[:mins2].to_i
                   else
                     0
                   end
            parsed_dt.change :hour => hour
            parsed_dt.change :mins => mins
            parsed_dt += 3600*24 if parsed_dt < current_dt and m[:day].nil? and m[:day2].nil? and m[:mdset].nil? #FIXME
          end
        elsif m[:hourdel] or m[:minsdel]
          n = 0
          n += if m[:hourdel].empty?
                 3600
               else
                 m[:hourdel]*3600
               end
          n += if m[:minsdel].empty?
                 60
               else
                 m[:minsdel]*60
               end
          parsed_dt += n #FIXME
        end
        {:action => :add_record, :time => parsed_dt, :msg => opt}
      end
    end
  end

  def backend_func
  end

  def do_func(model, params)
    puts params
  end
end

case ARGV[0]
when '--start'
  Rumpy.start MyBot
when '--stop'
  Rumpy.stop MyBot
end

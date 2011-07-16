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
      case opt
      when tz
        opt = 'help_tz'
      else
        opt = 'help'
      end
      {:action => :show_msg, :msg => opt}
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
      m = /^((((?<year>\d{4}|\d{2})-)?(?<month>\d{1,2})-(?<day>\d{1,2}))|((?<day>\d{1,2})\.(?<month>\d{1,2})(\.(?<year>\d{2}|\d{4}))?)|((?<mdnum>\d*)\s*(?<mdset>d|w)))?\s*(((?<hour>\d{1,2})((:(?<minute>\d{1,2}))\s*((?<hourset>a|p)\.?m\.?)|(:(?<minute>\d{1,2}))|((?<hourset>a|p)\.?m\.?)))|(((?<hourdel>\d*)h)?\s*((?<minutedel>\d*)m)?))$/.match cmd
      if m.nil?
        {:action => nil}
      else
        begin
#           result = Hash.new
#           m.names.each do |name|
#             result[name] = m[name]
#           end
#           return result
          year_set = date_set = time_set = date_del = time_del = false
          year_set = true unless m[:year].nil?
          date_set = true unless m[:day].nil?
          time_set = true unless m[:hour].nil?
          date_del = true unless m[:mdnum].nil? and m[:mdset].nil?
          time_del = true unless m[:hourdel].nil? and m[:minutedel].nil?
          current_dt = parsed_dt = Time.now
          if date_set
            #Retrieve full date
            year = m[:year]
            year = current_dt.year if year.nil?
            year, month, day = year.to_i, m[:month].to_i, m[:day].to_i
            year = 2000+year if year < 100
            parsed_dt = parsed_dt.change :year => year, :month => month, :day => day
            parsed_dt = parsed_dt.change :year => (year+1) if parsed_dt < current_dt and not year_set
          elsif date_del
            #Set up date from delay
            n = if m[:mdnum].empty?
                  1
                else 
                  m[:mdnum].to_i
                end
            n *= 7 if m[:mdset] == 'w' #weeks
            n *= 3600*24 #FIXME!!!
            parsed_dt += n
          end
          if time_set
            #Retrieve full time
            hour = m[:hour].to_i
            raise if hour > 12 and m[:hourset] == 'p'
            hour = 0 if hour == 12 and m[:hourset] == 'a' #EN style
            hour += 12 if hour != 12 and m[:hourset] == 'p'
            minute = if m[:minute].nil?
                       0
                     else
                       m[:minute].to_i
                     end
            parsed_dt = parsed_dt.change :hour => hour, :minute => minute #minute doesn't work
            parsed_dt += 3600*24 if parsed_dt < current_dt and not date_set and not date_del #FIXME
          elsif time_del
            #Set up time from delay
            n = 0
            if not m[:hourdel].nil?
              n += if m[:hourdel].empty?
                     3600
                   else
                     m[:hourdel].to_i*3600
                   end
            end
            if not m[:minutedel].nil?
              n += if m[:minutedel].empty?
                     60
                   else
                     m[:minutedel].to_i*60
                   end
            end
            parsed_dt += n #FIXME
          end
          if parsed_dt < current_dt
            {:action => :show_msg, :msg => 'passed_date'}
          elsif parsed_dt.to_i > 2147483647 # I really don't know better way here
            {:action => :show_msg, :msg => 'far_date'}
          else
            {:action => :add_record, :timestamp => parsed_dt.to_i, :msg => opt}
          end
        rescue
          {:action => :show_msg, :msg => 'wrong_date'}
        end
      end
    end
  end

  def backend_func
    sleep 1
    time = Time.now.to_i
    result = Array.new
    Note.find_each(:conditions => 'timestamp <= ' + time) do |note|
      result << [ note.user.jid, note.text ]
      note.destroy
    end
    result
  end

  def do_func(user, params)
    case params[:action]
    when :show_msg
      @lang[params[:msg]]
    when :add_record
      text = textparams[:msg]
      timestamp = params[:timestamp]
      if user.notes.create(:text => text, :timestamp => timestamp)
        @lang['record_added']
      else
        @lang['record_add_error']
      end
    when :show_records
      result = []
      id = 0
      user.notes.each do |note|
        id += 1
        result << "#{id}. #{note.text}"
      end
      result.join("\n")
    else
      @lang['misunderstand']
    end
  end
end

case ARGV[0]
when '--start'
  Rumpy.start Noty
when '--stop'
  Rumpy.stop Noty
end

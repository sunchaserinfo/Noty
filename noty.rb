#!/usr/bin/env ruby19

require 'rumpy'
require 'rubygems'
require 'tzinfo'

class Time
  def change(hash)
    arr = to_a
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
      when :min
        arr[1] = h[1]
      end
    end
    self.class.gm *arr
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
      when 'tz'
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
        result = Hash.new
        m.names.each do |name|
          result[name] = m[name]
        end
        result[:action] = :add_record
        result[:text] = opt
        result
      end
    end
  end

  def backend_func
    sleep 1
    time = Time.now.to_i
    result = Array.new
    Note.find_each(:conditions => ['timestamp <= ?', time]) do |note|
      note.text = @lang['emptymessage'] if note.text.empty?
      result << [ note.user.jid, note.text ]
      note.destroy
    end
    result
  end

  def do_func(user, params)
    case params[:action]
    when :show_msg
      @lang[params[:msg]]
    when :show_tz
      if user.timezone.nil?
        @lang['tz_not_set']
      else
        user.timezone
      end
    when :set_tz
      begin
        tz = TZInfo::Timezone.get params[:tz]
        user.timezone = tz.name
        user.save
        @lang['tz_set']
      rescue
        @lang['wrong_tz']
      end
    when :add_record
      return @lang['tz_not_set'] if user.timezone.nil?
      tz = TZInfo::Timezone.get user.timezone
      begin
        year_set = date_set = time_set = date_del = time_del = false
        year_set = true unless params[:year].nil?
        date_set = true unless params[:day].nil?
        time_set = true unless params[:hour].nil?
        date_del = true unless params[:mdnum].nil? and params[:mdset].nil?
        time_del = true unless params[:hourdel].nil? and params[:minutedel].nil?
        current_dt = parsed_dt = Time.now
        if date_set
          #Retrieve full date
          year = params[:year]
          year = current_dt.year if year.nil?
          year, month, day = year.to_i, params[:month].to_i, params[:day].to_i
          year = 2000+year if year < 100
          parsed_dt = parsed_dt.change :year => year, :month => month, :day => day
          parsed_dt = parsed_dt.change :year => (year+1) if parsed_dt < current_dt and not year_set
        elsif date_del
          #Set up date from delay
          n = if params[:mdnum].empty?
                1
              else 
                params[:mdnum].to_i
              end
          n *= 7 if params[:mdset] == 'w' #weeks
          n *= 3600*24 #FIXME!!!
          parsed_dt += n
        end
        if time_set
          #Retrieve full time
          hour = params[:hour].to_i
          raise if hour > 12 and params[:hourset] == 'p'
          hour = 0 if hour == 12 and params[:hourset] == 'a' #EN style
          hour += 12 if hour != 12 and params[:hourset] == 'p'
          minute = if params[:minute].nil?
                     0
                   else
                     params[:minute].to_i
                   end
          parsed_dt = parsed_dt.change :hour => hour, :minute => minute #minute doesn't work
          parsed_dt += 3600*24 if parsed_dt < current_dt and not date_set and not date_del #FIXME
        elsif time_del
          #Set up time from delay
          n = 0
          if not params[:hourdel].nil?
            n += if params[:hourdel].empty?
                   3600
                 else
                   params[:hourdel].to_i*3600
                 end
          end
          if not params[:minutedel].nil?
            n += if params[:minutedel].empty?
                   60
                 else
                   params[:minutedel].to_i*60
                 end
          end
          parsed_dt += n #FIXME
        end
        if parsed_dt < current_dt
          @lang['passed_date']
        elsif parsed_dt.to_i > 2147483647 # I really don't know better way here
          @lang['far_date']
        else
          text = params[:text]
          timestamp = parsed_dt.to_i
          if user.notes.create(:text => text, :timestamp => timestamp)
            @lang['record_added']
          else
            @lang['record_add_error']
          end
        end
      rescue
        @lang['wrong_date']
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

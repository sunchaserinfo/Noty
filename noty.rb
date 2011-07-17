#!/usr/bin/env ruby19

require './rumpy.rb'
require 'rubygems'
require 'tzinfo'
require 'date'

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
    self.class.utc *arr
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
    result = Hash.new
    addregexp = /^((?<dwdel>\d*)(?<dwset>d|w)|((?<year>\d{2}|\d{4})-)?(?<month>\d{1,2})-(?<day>\d{1,2})|(?<day>\d{1,2})\.(?<month>\d{1,2})(\.(?<year>\d{2}|\d{4}))?)?\s*\b((?<hour>\d{1,2})(:(?<min>\d{1,2}))?\s*\b((?<ap>a|p)\.?m\.?)?|((?<hourdel>\d{1,2})h)?\s*\b((?<mindel>\d{1,2})m)?)\s*\b(?<message>.*)$/
    if /^help\s*(.*)$/.match m.downcase do |md|
        result[:action] = :help
        result[:wut]    = md[1].strip
        result[:wut]    = 'en' if result[:wut].empty?
        true
      end
    elsif /^tz\s*(.*)/.match m do |md|
        result[:action] = :tz
        result[:wut]    = md[1].strip
      end
    elsif m == 'list' then
      result[:action] = :list
    elsif /^del\s*(.*)/.match m.downcase do |md|
        result[:action] = :del
        if md[1] == '*' then
          result[:wut] = :all
        else
          result[:wut]    = md[1].to_i
        end
      end
    elsif addregexp.match m do |md|
        result[:action]   = :add
        unless md[:dwset].nil?
          result[:daydel]   = if md[:dwdel].empty? then
                                1
                              else
                                md[:dwdel].to_i
                              end
          result[:daydel]  *= 7 if md[:dwset] == 'w'
        end
        result[:year]     = md[:year].to_i    unless md[:year].nil?
        result[:month]    = md[:month].to_i   unless md[:month].nil?
        result[:day]      = md[:day].to_i     unless md[:day].nil?
        unless md[:hourdel].nil?
          result[:del]    = if md[:hourdel].empty? then
                              3600
                            else
                              3600 * md[:hourdel].to_i
                            end
        end
        unless md[:mindel].nil?
          result[:del]  ||= 0
          result[:del]  += if md[:mindel].empty? then
                                60
                              else
                                60 * md[:mindel].to_i
                              end
        end
        result[:hour]     = md[:hour].to_i    unless md[:hour].nil?
        result[:min]      = md[:min].to_i     unless md[:min].nil?
        result[:ap]       = md[:ap]
        result[:msg]      = md[:message].strip

        result[:action] = nil if result[:daydel].nil? and result[:day].nil? and result[:del].nil? and result[:hour].nil? and result[:min].nil?
    end
    end

    result
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

  def tz(user, wut)
    if wut.empty?
      if user.timezone.nil?
        @lang['tz_not_set']
      else
        user.timezone
      end
    else
      begin
        _tz = TZInfo::Timezone.get wut
        user.timezone = _tz.name
        user.save
        @lang['tz_set']
      rescue TZInfo::InvalidTimezoneIdentifier
        @lang['wrong_tz']
      end
    end
  end

  def change_date(params, current)
    if params[:month] then
      year_omitted = params[:year].nil?
      params[:year] ||= current.year
      params[:year] += 2000 if params[:year] < 100
      wanted = current.change :year => params[:year], :month => params[:month], :day => params[:day]
      if wanted < current then
        if year_omitted then
          wanted = wanted.change :year => (params[:year] + 1)
        else
          raise ArgumentError, 'wrong date'
        end
      end
      wanted
    elsif params[:daydel] then
      wanted = (current.to_date + params[:daydel]).to_time
    end
  end

  def change_time(params, current, wanted, dc)
    if params[:hour] then
      raise ArgumentError, 'wrong hour' if params[:hour] > 12 and params[:ap] == 'p'
      params[:hour] = 0 if params[:hour] == 12 and params[:ap] == 'a'
      params[:hour] += 12 if params[:hour] != 12 and params[:ap] == 'p'
      params[:min] ||= 0
      wanted = wanted.change :hour => params[:hour], :min => params[:min]
      if wanted < current then
        if date_changed then
          raise ArgumentError, 'wrong date-time'
        else
          wanted = wanted.to_datetime.next.to_time
        end
      end
      wanted
    elsif params[:del] then
      wanted += params[:del]
    end
  end

  def add(user, params)
    if user.timezone.nil? then
      @lang['tz_not_set']
    else
      tz = TZInfo::Timezone.get user.timezone
      begin
        current = tz.now
        wanted = change_date params, current
        date_changed = if wanted.nil? then
                         wanted = current
                         false
                       else
                         true
                       end

        wanted_ = change_time params, current, wanted, date_changed
        wanted = wanted_ unless wanted_.nil?

        if wanted <= current then
          @lang['passed_date']
        elsif wanted.to_i > 2147483647 then
          @lang['far_date']
        else
          params[:msg] = @lang['empty_message'] if params[:msg].empty?
          if user.notes.create :text => params[:msg], :timestamp => (tz.local_to_utc wanted).to_i then
            @lang['record_added'] % wanted.strftime('%Y-%m-%d %H:%M:%S')
          else
            @lang['record_add_error']
          end
        end
      rescue ArgumentError => e
        @lang['wrong_date'] % e.message
      end
    end
  end

  def do_func(user, params)
    case params[:action]
    when :help
      @lang['help_' + params[:wut]]
    when :tz
      tz user, params[:wut]
    when :add
      add user, params
    when :list
      result = ""
      id = 0
      user.notes.each do |note|
        result << "#{id += 1}. #{Time.at(note.timestamp).strftime('%Y-%m-%d %H:%M:%S')} :: #{note.text}\n"
      end
      result
    when :del
      if params[:wut] == :all then
        user.notes.clear
        @lang['list_cleared']
      else
        id = 0
        user.notes.each do |note|
          break note.destroy if (id += 1) == params[:wut]
        end

        if id == params[:wut] then
          @lang['deleted']
        else
          @lang['not_found']
        end
      end
    else
      @lang['misunderstand']
    end
  end
end

case ARGV[0]
when 'start'
  Rumpy.start Noty
when 'stop'
  Rumpy.stop Noty
when 'restart'
  Rumpy.stop Noty
  Rumpy.start Noty
end

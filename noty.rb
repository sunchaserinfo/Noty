#!/usr/bin/env ruby

require 'rubygems'
require 'rumpy'
require 'tzinfo'
require 'active_support/core_ext/time/calculations'
require 'oniguruma'

class Noty
  include Rumpy::Bot

  # Cool regexp
  Addregexp = Oniguruma::ORegexp.new '^(((?<weeks>\d*)w)?\s*\b((?<days>\d*)d)?\s|((?<year_>\d{2}|\d{4})-)?(?<month_>\d{1,2})-(?<day_>\d{1,2})|(?<day>\d{1,2})\.(?<month>\d{1,2})(\.(?<year>\d{2}|\d{4}))?)?\s*\b((?<hour>\d{1,2})(:(?<min>\d{1,2}))?\s*\b((?<ap>a|p)\.?m\.?)?|((?<hours>\d*)h)?\s*\b((?<minutes>\d*)m)?)\s*\b(?<message>.*)$', 'i', 'utf8'

  def initialize
    @config_path = 'config'
    @log_file    = 'noty.log'
    @log_level   = Logger::INFO
    @models_path = File.dirname(__FILE__) + '/models/*.rb'
    @main_model  = :user
  end

  def parser_func(m)
    m.strip!
    spl = m.split ' ', 2
    spl[0].downcase!
    spl[1]

    result = Hash.new

    case spl[0]
    when 'help'
      result[:action] = :help
      spl[1]        ||= 'text'
      result[:wut]    = spl[1].strip
    when 'tz'
      result[:action ] = :tz
      spl[1]         ||= ''
      result[:wut]     = spl[1].strip
    when 'list'
      result[:action] = :list
    when 'del'
      result[:action] = :del
      result[:wut]    = if spl[1] == '*' then
                          :all
                        else
                          spl[1].to_i
                        end
    when 'debug'
      result[:action] = :debug
      result[:wut] = spl[1]
    else

      md = Addregexp.match m
      if md then
        result[:action] = :add

        for symbol in [:ap, :message] do
          result[symbol] = md[symbol] if md[symbol]
        end

        # hack for different date layouts (yy-mm-dd vs dd.mm.yy)
        for symbol in [:year_, :month_, :day_] do
          result[symbol.to_s.tr('_', '').to_sym] = md[symbol].to_i if md[symbol]
        end

        for symbol in [:days, :weeks, :year, :month, :day, :hours, :minutes,
                       :hour, :min] do
          result[symbol] =  if md[symbol].empty? then
                              1
                            else
                              md[symbol].to_i
                            end if md[symbol]
        end

        result[:action] = nil unless result[:days] or result[:weeks] or
                                     result[:day] or result[:hours] or
                                     result[:minutes] or result[:hour] or result[:min]
      end
    end

    result
  end

  def backend_func
    sleep 1
    time   = Time.now.to_i
    result = Array.new
    Note.find_each(:conditions => ['timestamp <= ?', time]) do |note|
      result << [ note.user.jid, note.text ] if note.user
      note.destroy
    end
    result
  end

  def do_func(user, params)
    case params[:action]
    when :debug
      case params[:wut]
      when 'times'
        p = Process.times
        "User::#{p.utime}\t\tSystem::#{p.stime}"
      when 'stat'
        "Users::#{User.count}\t\tNotes::#{Note.count}"
      when 'users'
        users = Array.new
        User.find_each do |user|
          users << "(#{user.jid}|#{user.notes.count})"
        end
        users.join ', '
      else
        @lang['misunderstand']
      end
    when :help
      if params[:wut] == 'tz'
        TZInfo::Timezone.all.inject('') do |result, tz|
          result << "#{tz.name}\n"
        end
      else
        @lang['help_' + params[:wut]] || @lang['misunderstand']
      end
    when :tz
      tz user, params[:wut]
    when :add
      add user, params
    when :list
      if user.timezone.nil? then
        @lang['tz_not_set']
      else
        if user.notes.empty?
          @lang['list_empty']
        else
          result = ''
          id = 0
          tz = TZInfo::Timezone.get user.timezone

          user.notes.find_each do |note|
            result << "#{id += 1}. #{tz.utc_to_local(Time.at(note.timestamp).utc).
                                     strftime('%Y-%m-%d %H:%M:%S')} #{note.text}\n"
          end
          result
        end
      end
    when :del
      if params[:wut] == :all then
        user.notes.destroy_all
        @lang['list_cleared']
      elsif params[:wut] != 0
        id = 0
        user.notes.find_each do |note|
          break note.destroy if (id += 1) == params[:wut]
        end

        if id == params[:wut] then
          @lang['record_deleted']
        else
          @lang['record_not_found']
        end
      else
        @lang['misunderstand']
      end
    else
      @lang['misunderstand']
    end
  end

  def tz(user, wut)
    if wut.empty?
      user.timezone || @lang['tz_not_set']
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

  def add(user, params)
    if user.timezone.nil? then
      @lang['tz_not_set']
    else
      tz = TZInfo::Timezone.get user.timezone
      begin
        current = tz.now

        wanted = select_datetime params, current

        if wanted <= current then
          @lang['passed_date']
        elsif wanted.to_i > 2147483647 then
          @lang['far_date']
        else
          params[:message] = @lang['empty_message'] if params[:message].empty?
          if user.notes.create  :text => params[:message],
                                :timestamp => tz.local_to_utc(wanted).to_i then
            @lang['record_added'] % wanted.strftime('%Y-%m-%d %H:%M:%S')
          else
            @lang['record_add_error']
          end
        end
      rescue ArgumentError
        @lang['wrong_date']
      end
    end
  end

  def select_datetime(params, current)
    prepare_pars_results params

    wanted = current

    wanted = current.change :year => params[:year], :month => params[:month], :day => params[:day]

    # if selected date has past we must test, if year was omitted
    # if so, simply increase current year
    # else --- IT'S PROBLEM
    if params[:year_omitted] then
      wanted = wanted.next_year
    else
      raise ArgumentError
    end if wanted < current

    wanted = wanted.advance :days => params[:days], :weeks => params[:weeks]

    date_changed = (wanted != current)

    wanted = wanted.change :hour => params[:hour], :min => params[:min]

    # if selected time has past we must test, have we changed date before
    # if so then IT'S PROBLEM because user definitely types wrong datetime
    # else increase day
    if date_changed then
      raise ArgumentError
    else
      wanted = wanted.tomorrow
    end if wanted < current

    wanted.advance :hours => params[:hours], :minutes => params[:minutes]
  end

  def prepare_pars_results(pars_results)
    # after parsing we got next values in pars_results
    # days --- the delay in days
    # weeks --- the delay in weeks
    # year  --- can be omitted, than current year will be used
    # month, day
    # hour, (min) --- hour and minutes (optional)
    # ap --- p stands for p.m., a stands for a.m.. Can be nil
    # hours --- delay in hours
    # minutes --- delay in minutes

    pars_results[:year] += 2000 if pars_results[:year] and pars_results[:year] < 100

    pars_results[:year_omitted] = pars_results[:year].nil?

    if pars_results[:hour]
      raise ArgumentError if pars_results[:ap] == 'p' and pars_results[:hour] > 12
      pars_results[:hour]   = 0 if pars_results[:ap] == 'a' and pars_results[:hour] == 12
      pars_results[:hour]  += 12 if pars_results[:ap] == 'p' and pars_results[:hour] != 12
      pars_results[:min]  ||= 0
    end

    # the values in pars_results have slightly changed now
    # if year was set by last 2 digits, it will be expanded
    # hour is now in [0..23]
  end
end

case ARGV[0]
when 'run'
  Rumpy.run Noty
when 'start'
  Rumpy.start Noty
when 'stop'
  Rumpy.stop Noty
when 'restart'
  Rumpy.stop Noty
  Rumpy.start Noty
end

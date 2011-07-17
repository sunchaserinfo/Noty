#!/usr/bin/env ruby

require 'rubygems'
require 'rumpy'
require 'tzinfo'
require 'date'
require 'oniguruma'

class Noty
  include Rumpy::Bot

  # Cool regexp
  Addregexp = Oniguruma::ORegexp.new '^((?<dwdel>\d*)(?<dwset>d|w)|((?<year_>\d{2}|\d{4})-)?(?<month_>\d{1,2})-(?<day_>\d{1,2})|(?<day>\d{1,2})\.(?<month>\d{1,2})(\.(?<year>\d{2}|\d{4}))?)?\s*\b((?<hour>\d{1,2})(:(?<min>\d{1,2}))?\s*\b((?<ap>a|p)\.?m\.?)?|((?<hourdel>\d{1,2})h)?\s*\b((?<mindel>\d{1,2})m)?)\s*\b(?<message>.*)$', 'i', 'utf8'

  def initialize
    @config_path = 'config'
    @models_path = File.dirname(__FILE__) + '/models/*.rb'
    @main_model  = :user
  end

  def parser_func(m)
    m.strip!
    spl = m.split ' ', 2
    spl[0].downcase!

    result = Hash.new

    if spl[0] == 'help' then
      result[:action] = :help
      spl[1]        ||= 'text'
      result[:wut]    = spl[1].strip
    elsif spl[0] == 'tz' then
      result[:action ] = :tz
      spl[1]         ||= ''
      result[:wut]     = spl[1].strip
    elsif spl[0] == 'list' then
      result[:action] = :list
    elsif spl[0] == 'del' then
      result[:action] = :del
      result[:wut]    = if spl[1] == '*' then
                          :all
                        else
                          spl[1].to_i
                        end
    else

      md =  Addregexp.match m
      if md then
        result[:action]   = :add
        for symbol in [:dwset, :ap, :message] do
          result[symbol] = md[symbol] if md[symbol]
        end

        # hack for ruby18 with oniguruma as a gem
        for symbol in [:year_, :month_, :day_] do
          result[symbol.to_s.tr('_', '').to_sym] = md[symbol].to_i if md[symbol]
        end

        for symbol in [:dwdel, :year, :month, :day, :hourdel, :mindel, :hour, :min] do
          result[symbol] =  if md[symbol].empty? then
                              1
                            else
                              md[symbol].to_i
                            end if md[symbol]
        end

        result[:action] = nil unless result[:dwdel] or result[:day] or result[:hourdel] or
                              result[:mindel] or result[:hour] or result[:min]
      end
    end

    result
  end

  def backend_func
    sleep 5
    time   = Time.now.to_i
    result = Array.new
    Note.find_each(:conditions => ['timestamp <= ?', time]) do |note|
      result << [ note.user.jid, note.text ]
      note.destroy
    end
    result
  end

  def do_func(user, params)
    case params[:action]
    when :help
      if params[:wut] == 'tz'
        result = ''
        TZInfo::Timezone.all.each { |tz| result << "#{tz.name}\n" }
        result
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
        if user.notes.count == 0
          @lang['list_empty']
        else
          result = ''
          id = 0
          tz = TZInfo::Timezone.get user.timezone
          user.notes.each do |note|
            result << "#{id += 1}. #{tz.utc_to_local(Time.at note.timestamp).strftime('%Y-%m-%d %H:%M:%S')} #{note.text}\n"
          end
          result
        end
      end
    when :del
      if params[:wut] == :all then
        user.notes.clear
        @lang['list_cleared']
      elsif params[:wut] != 0
        id = 0
        user.notes.each do |note|
          break note.destroy if (id += 1) == params[:wut]
        end

        if id == params[:wut] then
          @lang['deleted']
        else
          @lang['not_found']
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
          if user.notes.create :text => params[:message], :timestamp => (tz.local_to_utc wanted).to_i then
            @lang['record_added'] % wanted.strftime('%Y-%m-%d %H:%M:%S')
          else
            @lang['record_add_error']
          end
        end
      rescue StandardError
        @lang['wrong_date']
      end
    end
  end

  def select_datetime(params, current)
    prepare_pars_results params

    date_changed = true
    wanted = current

    if params[:month] then
      params[:year] ||= current.year
      wanted = current.change :year => params[:year], :month => params[:month], :day => params[:day]
      if wanted < current then
        if params[:year_omitted] then
          wanted = wanted.change :year => (params[:year] + 1)
        else
          raise ArgumentError
        end
      end
    elsif params[:dwdel] then #if user sets the delay in days|weeks
      wanted = (current.to_date + params[:dwdel]).to_time
    else
      date_changed = false
    end

    if params[:hour] then
      wanted = wanted.change :hour => params[:hour], :min => params[:min]
      if wanted < current then
        if date_changed then
          raise ArgumentError
        else
          wanted = wanted.to_datetime.next.to_time
        end
      end
    elsif params[:del] then #if user sets delay in hours|minutes
      wanted += params[:del]
    end

    wanted
  end

  def prepare_pars_results(pars_results)
    # after parsing we got next values in pars_results
    # dwdel --- the delay in days|weeks
    # dwset --- if dwdel stands for delay in days or in weeks
    # year  --- can be omitted, than current year will be used
    # month, day
    # hour, (min) --- hour and minutes (optional)
    # ap --- p stands for p.m., a stands for a.m.. Can be nil
    # hourdel --- delay in hours
    # mindel --- delay in minutes

    pars_results[:dwdel] *= 7 if pars_results[:dwset] == 'w'

    pars_results[:year] += 2000 if pars_results[:year] and pars_results[:year] < 100

    pars_results[:year_omitted] = pars_results[:year].nil?

    if pars_results[:hour]
      raise ArgumentError if pars_results[:ap] == 'p' and pars_results[:hour] > 12
      pars_results[:hour]   = 0 if pars_results[:ap] == 'a' and pars_results[:hour] == 12
      pars_results[:hour]  += 12 if pars_results[:ap] == 'p' and pars_results[:hour] != 12
      pars_results[:min]  ||= 0
    end

    pars_results[:del] = 3600 * pars_results[:hourdel] if pars_results[:hourdel]
    if pars_results[:mindel] then
      pars_results[:del] ||= 0
      pars_results[:del]  += 60 * pars_results[:mindel]
    end

    # the values in pars_results have slightly changed now
    # dwdel set the delay in days
    # if year was set by last 2 digits, it will be expanded
    # hour is now in [0..23]
    # del stands for delay in seconds
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

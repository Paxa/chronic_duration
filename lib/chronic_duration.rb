require 'numerizer' unless defined?(Numerizer)
module ChronicDuration
  FORMATS = {
    :micro => {
      :names => {:years => 'y', :months => 'm', :days => 'd', :hours => 'h', :minutes => 'm', :seconds => 's'},
      :joiner => ''
    },
    
    :short => {
      :names => {:years => 'y', :months => 'm', :days => 'd', :hours => 'h', :minutes => 'm', :seconds => 's'}
    },
    
    :default => {
      :names => {:years => ' yr', :months => ' mo', :days => ' day', :hours => ' hr', :minutes => ' min', :seconds => ' sec',
      :pluralize => true}
    },
    
    :long => {
      :names => {:years => ' year', :months => ' month', :days => ' day', :hours => ' hour', :minutes => ' minute', :seconds => ' second', 
      :pluralize => true}
    },
    
    :chrono => {
      :names => {:years => ':', :months => ':', :days => ':', :hours => ':', :minutes => ':', :seconds => ':', :keep_zero => true},
      :joiner => '',
      :process => lambda do |str|
        # Pad zeros
        # Get rid of lead off times if they are zero
        # Get rid of lead off zero
        # Get rid of trailing :
        str.gsub(/\b\d\b/) { |d| ("%02d" % d) }.gsub(/^(00:)+/, '').gsub(/^0/, '').gsub(/:$/, '')
      end
    },
    
    :iso8601 => {
      :names => {:years => 'Y', :months => 'M', :days => 'D', :hours => 'H', :minutes => 'M', :seconds => 'S'},
      :joiner => '',
      :process => lambda {|str| "P#{str}" }
    }
  }
  extend self
  
  class DurationParseError < StandardError
  end
  
  @@raise_exceptions = false
  
  def self.raise_exceptions
    !!@@raise_exceptions
  end
  
  def self.raise_exceptions=(value)
    @@raise_exceptions = !!value
  end
  
  @@rates = {
    :minutes  => 60,
    :hours    => 60 * 60,
    :days     => 60 * 60 * 24,
    :months   => 60 * 60 * 24 * 30,
    :years    => 60 * 60 * 24 * 365.25
  }
  
  # Given a string representation of elapsed time,
  # return an integer (or float, if fractions of a
  # second are input)
  def parse(string, opts = {})
    result = calculate_from_words(cleanup(string), opts)
    result == 0 ? nil : result
  end  
  
  # Given an integer and an optional format,
  # returns a formatted string representing elapsed time
  def output(seconds, opts = {})
    date = { :years => 0, :months => 0, :days => 0, :hours => 0, :minutes => 0 }
    
    # drop tail zero (5.0 => 5)
    if seconds.is_a?(Float) && seconds % 1 == 0.0
      seconds = seconds.to_i
    end
    
    decimal_places = seconds.to_s.split('.').last.length if seconds.is_a?(Float)
    
    @@rates.to_a.sort_by(&:last).reverse.each do |key, value|
      date[key] = (seconds / value).to_i
      seconds = seconds % value
    end
    date[:seconds] = seconds
    
    format_info = FORMATS[opts[:format]] || FORMATS[:default]
    dividers = format_info[:names]
    joiner = format_info[:joiner] || ' '
    process = format_info[:joiner] || nil
    
    result = []
    [:years, :months, :days, :hours, :minutes, :seconds].each do |t|
      num = date[t]
      num = ("%.#{decimal_places}f" % num) if num.is_a?(Float) && t == :seconds
      result << humanize_time_unit( num, dividers[t], dividers[:pluralize], dividers[:keep_zero] )
    end

    # insert 'T' if its iso8601 && and time is not zero
    if opts[:format] == :iso8601 && !result[3..5].join.empty?
      result.insert(3, 'T') 
    end
    
    result = result.join(joiner).squeeze(' ').strip
    result = format_info[:process].call(result) if format_info[:process]
    
    result.length == 0 ? nil : result
  end
  
private
  
  def humanize_time_unit(number, unit, pluralize, keep_zero)
    return '' if number.to_s == '0' && !keep_zero
    res = "#{number}#{unit}"
    # A poor man's pluralizer
    res << 's' if !(number.to_s == '1') && pluralize
    res
  end
  
  def calculate_from_words(string, opts)
    val = 0
    words = string.split(' ')
    words.each_with_index do |v, k|
      if v =~ float_matcher
        val += (convert_to_number(v) * duration_units_seconds_multiplier(words[k + 1] || (opts[:default_unit] || 'seconds')))
      end
    end
    val
  end
  
  def cleanup(string)
    res = string.downcase
    res = filter_by_type(Numerizer.numerize(res))
    res = res.gsub(float_matcher) {|n| " #{n} "}.squeeze(' ').strip
    res = filter_through_white_list(res)
  end
  
  def convert_to_number(string)
    string.to_f % 1 > 0 ? string.to_f : string.to_i
  end
  
  def duration_units_list
    %w(seconds minutes hours days weeks months years)
  end
  def duration_units_seconds_multiplier(unit)
    return 0 unless duration_units_list.include?(unit)
    case unit
    when 'years';   31536000 # doesn't accounts for leap years
    when 'months';  3600 * 24 * 30
    when 'weeks';   3600 * 24 * 7
    when 'days';    3600 * 24
    when 'hours';   3600
    when 'minutes'; 60
    when 'seconds'; 1
    end
  end
  
  def error_message
    'Sorry, that duration could not be parsed'
  end
  
  # Parse 3:41:59 and return 3 hours 41 minutes 59 seconds
  def filter_by_type(string)
    if string.gsub(' ', '') =~ /#{float_matcher}(:#{float_matcher})+/
      res = []
      string.gsub(' ', '').split(':').reverse.each_with_index do |v,k|
        return unless duration_units_list[k]
        res << "#{v} #{duration_units_list[k]}"
      end
      res = res.reverse.join(' ')
    else
      res = string
    end
    res
  end
  
  def float_matcher
    /[0-9]*\.?[0-9]+/
  end
  
  # Get rid of unknown words and map found
  # words to defined time units
  def filter_through_white_list(string)
    res = []
    string.split(' ').each do |word|
      if word =~ float_matcher
        res << word.strip
        next
      end
      stripped_word = word.strip.gsub(/^,/, '').gsub(/,$/, '')
      if mappings.has_key?(stripped_word)
        res << mappings[stripped_word]
      elsif !join_words.include?(stripped_word) and ChronicDuration.raise_exceptions
        raise DurationParseError, "An invalid word #{word.inspect} was used in the string to be parsed."
      end
    end
    res.join(' ')
  end
  
  def mappings
    { 
      'seconds' => 'seconds',
      'second'  => 'seconds',
      'secs'    => 'seconds',
      'sec'     => 'seconds',
      's'       => 'seconds',
      'minutes' => 'minutes',
      'minute'  => 'minutes',
      'mins'    => 'minutes',
      'min'     => 'minutes',
      'm'       => 'minutes',
      'hours'   => 'hours',
      'hour'    => 'hours',
      'hrs'     => 'hours',
      'hr'      => 'hours',
      'h'       => 'hours',
      'days'    => 'days',
      'day'     => 'days',
      'dy'      => 'days',
      'd'       => 'days',
      'weeks'   => 'weeks',
      'week'    => 'weeks',
      'w'       => 'weeks',
      'months'  => 'months',
      'mos'     => 'months',
      'month'   => 'months',
      'years'   => 'years',
      'year'    => 'years',
      'yrs'     => 'years',
      'y'       => 'years'
    }
  end
  
  def join_words
    ['and', 'with', 'plus']
  end
end

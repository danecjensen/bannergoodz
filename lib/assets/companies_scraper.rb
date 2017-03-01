require 'nokogiri'
require 'csv'
require 'open-uri'
require 'selenium-webdriver'
require 'pry'


# Feel free to do as much or as little as you want on this project.  I saw you did some web scraping and thought this would be a fun project for you to try out.  We will talk about it briefly on Thursday.  
# 
#   I made a repo as a starting point: https://github.com/danecjensen/bannergoodz.  If you clone that repo there’s a csv file in the main directory called companylist.csv.  For each website in that csv I want you to pull the following information:
# 
#   <meta name="description" content="" />
# <meta property="og:title" content=”">
# <meta property="og:image" content="" />
# (a profile picture from facebook page or instagram page that corresponds to the website)
# 
# Then insert that information in the Rails model Brand (https://github.com/danecjensen/bannergoodz/blob/master/app/models/brand.rb).
# 
#   Specifically (where b = Brand.new):
#   <meta name="description" content="" /> ----> b.desc
# <meta property="og:title" content=""> ----> b.name
# <meta property="og:image" content="" /> ----> b.card_image (this is an url string)
# (a profile picture from facebook page or instagram page that corresponds to the website) ----> b.profile_image (this is an url string)


# For now, scrapes website information based on the following root-level file:
# companylist.csv
class CompaniesScraper
  def initialize
    @source = File.expand_path('../../../companylist.csv', __FILE__)
    @request_handler = RequestHandler.new
    @co_parser = CompaniesParser.new
  end

  def scrape
    @co_parser.start_driver
    CSV.foreach(@source, headers: true) do |row|
      html = @request_handler.page_info(row['URL'])
      @co_parser.parse(html, row['URL'], row['Anchor']) if html
    end
    @co_parser.stop_driver
  end
end

# Handles the parsing of all data both static and AJAX-loaded data
class CompaniesParser
  META_DESCRIPTION = "meta[name='description']".freeze
  META_TITLE = "meta[property='og:title']".freeze
  META_IMAGE = "meta[property='og:image']".freeze
  FACEBOOK_SELECTOR = 'a[href*="facebook.com"]'.freeze
  INSTAGRAM_SELECTOR = 'a[href*="instagram.com"]'.freeze
  SPECIAL_CHARACTERS = ['&', '?', '.']

  def parse(html, url, name)
    @html = html
    @url = url
    @name = cleanse_name(name)
    reset_vars
    set_static_meta_info
    set_static_social_links
    ensure_data_with_js
    Brand.create({
      desc: @meta_info[:description],
      name: @meta_info[:title],
      card_img: @meta_info[:image],
      facebook_url: @social_links[:facebook],
      instagram_url: @social_links[:instagram],
      profile_img: @profile_picture
    })
  end

  def start_driver
    @driver = Selenium::WebDriver.for :chrome, switches: %w[--ignore-certificate-errors --disable-translate], driver_path: '/home/durendal/workspace/chromedriver'
  end

  def stop_driver
    @driver.quit
  end

  private

  def reset_vars
    @meta_info = { description: '', title: '', image: '' }
    @social_links = { facebook: '', instagram: '' }
    @profile_picture = ''
  end

  def cleanse_name(name)
    name_arr = name_as_arr(name)
    remove_special_chars(remove_special_char_words(name_arr))
  end

  def name_as_arr(name)
    return [name.downcase] unless name.include? ' '
    name.strip.split(' ')
  end

  def remove_special_char_words(name_arr)
    name_arr.delete_if do |n|
      result = false
      SPECIAL_CHARACTERS.each do |c|
        if c == n
          result = true
          break
        end
      end
      result
    end
  end

  def remove_special_chars(name_arr)
    name_arr.each do |n|
      SPECIAL_CHARACTERS.each do |c|
        n.gsub! /#{Regexp.escape(c)}/, ''
      end
    end
  end

  # Creates a CSS selector based on a company name. Handles names of multiple
  # words and/ore that have special characters:
  #
  # Ex:
  #
  # The Bouqs => "[href*='the'][href*='bouqs']"
  # Frank & Oak => "[href*='frank'][href*='oak']"
  # 
  # Possible TODO: Make more robust to where you don't have to rely on Co. name
  #
  def css_name_selector
    @name.reduce('') do |sum, n|
      sum + "[href*='#{n.downcase}']"
    end
  end

  # Same as css_name_selector, but ignores case (only works with CSS4 and above)
  def css4_name_selector
    @name.reduce('') do |sum, n|
      sum + "[href*='#{n.downcase}' i]"
    end
  end

  # Returns css4_name_selectors as an array
  def css4_name_selectors
    @name.map do |n|
      "[href*='#{n.downcase}' i]"
    end
  end

  # Sets static meta information. Static implies Nokogiri
  def set_static_meta_info
    @meta_info.each do |k, _|
      data = @html.css(self.class.const_get("META_#{k.to_s.upcase}"))[0]
      @meta_info[k] = data['content'] if data
    end
  end

  # Sets static social links information. Static implies Nokogiri
  def set_static_social_links
    @social_links.each do |k, _|
      data = @html.css(self.class.const_get("#{k.to_s.upcase}_SELECTOR") + css_name_selector)[0]
      @social_links[k] = ensure_valid_link(data['href']) if data
    end
  end

  # So far, only one of these.
  # NOTE: Could make more robust in the future
  def ensure_valid_link(link)
    if link.start_with? '//'
      link = 'https:' + link
    end
    link
  end

  def check_js_loaded_meta_info
    @meta_info.each do |k,v|
      next unless v.empty?
      begin
        el = @driver.find_element(:css, self.class.const_get("META_#{k.to_s.upcase}"))
        @meta_info[k] = el['content']
      rescue Selenium::WebDriver::Error::NoSuchElementError
      end
    end
  end

  def check_js_loaded_social_links
    @social_links.each do |k,v|
      next unless v.empty?

      # Many social media links contain only part of the company's name. For
      # example:
      #
      # Sole Bicycles => facebook.com/brilliantbicycles
      css4_name_selectors.each do |s|
        selenium_search_wrapper do |el_type|
          el_type = k
          el = @driver.find_element(:css, self.class.const_get("#{k.to_s.upcase}_SELECTOR") + s)
          @social_links[k] = el['href']
        end
      end
    end
  end

  def check_social_links_without_name
    @social_links.each do |k,v|
      next unless v.empty?
      selenium_search_wrapper do |el_type|
        el_type = k
        el = @driver.find_element(:css, self.class.const_get("#{k.to_s.upcase}_SELECTOR"))
        @social_links[k] = el['href']
      end
    end
  end

  def all_social_links_empty?
    @social_links.each { |_,v| return false unless v.empty? }
    true
  end

  def check_js_loaded_profile_pic
    @social_links.each do |k, v|
      break unless @profile_picture.empty?
      next if v.empty?
      @driver.navigate.to v
      selenium_search_wrapper do |el_type|
        el_type = k
        if k == :facebook
          el = @driver.find_element(:css, "a[aria-label='Profile picture'] img")
        else
          el = @driver.find_element(:css, "header img[class='_8gpiy _r43r5']")
        end
        @profile_picture = el['src'] if el
      end
    end
  end

  # Request handler for Selenium-specific errors
  def selenium_search_wrapper
    element_type = ''
    begin
      yield(element_type) if block_given?
    rescue Selenium::WebDriver::Error::NoSuchElementError, Selenium::WebDriver::Error::TimeOutError => e
      # Handle too much JS loading
      @driver.execute_script('window.stop();') if e.message.include? 'timeout'
    end
  end

  def ensure_data_with_js
    @driver.manage.timeouts.page_load = 60

    selenium_search_wrapper do
      @driver.navigate.to @url
    end

    check_js_loaded_meta_info
    p @meta_info 

    check_js_loaded_social_links
    p @social_links

    # Last ditch effort to find social media links to get profile picture
    check_social_links_without_name if all_social_links_empty?
    p @social_links

    check_js_loaded_profile_pic
    p @profile_picture
  end
end

# Handles the structure of HTTP requests
class RequestHandler

  # Retrieves page info as a Nokogiri::HTML object
  # Returns nil if an error-less uri cannot be found (in other words, no
  # NokogiriHTML object can be created)
  def page_info(url)
    uri ||= URI.parse(url)
    tries = 3

    begin
      uri.open(redirect: false)
    rescue OpenURI::HTTPRedirect, OpenURI::HTTPError => e
      if e.class == OpenURI::HTTPRedirect
        uri = e.uri
        retry if (tries -= 1) > 0
        raise
      elsif e.class == OpenURI::HTTPError
        # Handles 404s
        # TODO: Possibly delete or make not of this?
        return nil
      end
    end

    Nokogiri::HTML(open(uri))
  end
end

CompaniesScraper.new.scrape

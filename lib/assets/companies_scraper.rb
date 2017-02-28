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
    cnt = 0
    CSV.foreach(@source, headers: true) do |row|
      cnt += 1
      next if cnt <= 3
      html = @request_handler.page_info(row['URL'])
      @co_parser.parse(html, row['URL'], row['Anchor']) if html
    end
  end

#    pecifically (where b = Brand.new):
#      <meta name="description" content="" /> ----> b.desc
#    <meta property="og:title" content=""> ----> b.name
#    <meta property="og:image" content="" /> ----> b.card_image (this is an url string)
#    (a profile picture from facebook page or instagram page that corresponds to the website) ----> b.profile_image (this is an url string)
end

# Handles the parsing of all data both static and AJAX-loaded data
class CompaniesParser
  META_DESCRIPTION = "meta[name='description']".freeze
  META_TITLE = "meta[property='og:title']".freeze
  META_IMAGE = "meta[property='og:image']".freeze
  FACEBOOK_SELECTOR = 'a[href*="//www.facebook"]'.freeze
  INSTAGRAM_SELECTOR = 'a[href*="//www.instagram"]'.freeze
  SPECIAL_CHARACTERS = ['&']

  def parse(html, url, name)
    @html = html
    @url = url
    @name = cleanse_name(name)
    @meta_info = {
      description: '',
      title:       '',
      image:       ''
    }
    set_static_meta_info
    @social_links = {
      facebook:    '',
      instagram:   ''
    }
    @profile_picture = ''
    set_static_social_links
    ensure_data_with_js
    # create model
  end

  private

  def cleanse_name(name)
    name.strip.split(' ').delete_if do |n|
      result = false
      SPECIAL_CHARACTERS.each do |c|
        if c == n
          result = true
          break
        end
      end
    end
  end

  # Creates a CSS selector based on a company name. Handles names of multiple
  # words and/ore that have special characters:
  #
  # Ex:
  #
  # The Bouqs => ["[href*='the']", "href*='bouqs'"]
  # Frank & Oak => ["href*='frank'", "href*='oak'"]
  # 
  def css_name_selector
    @name.reduce('') do |sum, n|
      sum + "[href*='#{n.downcase}']"
    end
  end

  def set_static_meta_info
    @meta_info.each do |k, _|
      data = @html.css(self.class.const_get("META_#{k.to_s.upcase}"))[0]
      @meta_info[k] = data['content'] if data
    end
  end

  def set_static_social_links
    @social_links.each do |k, _|
      data = @html.css(self.class.const_get("#{k.to_s.upcase}_SELECTOR") + css_name_selector)[0]
      @social_links[k] = data['href'] if data
    end
  end

  def check_js_loaded_meta_info
    @meta_info.each do |k,v|
      next unless v.empty?
      begin
        el = @driver.find_element(:css, self.class.const_get("META_#{k.to_s.upcase}"))
        @meta_info[k] = el['content']
      rescue Selenium::WebDriver::Error::NoSuchElementError
        puts "No #{k} element found"
      end
    end
  end

  def check_js_loaded_social_links
    if @social_links.values.keep_if { |s| !s.empty? }.empty?
      @social_links.each do |k,_|
        begin
          el = @driver.find_element(:css, self.class.const_get("#{k.to_s.upcase}_SELECTOR") + css_name_selector)
          @social_links[k] = el['href']
        rescue Selenium::WebDriver::Error::NoSuchElementError
          puts "No #{k} element found"
        end
      end
    end
  end

  def check_js_loaded_profile_pic
    @social_links.each do |k, v|
      break unless @profile_picture.empty?
      next if v.empty?
      @driver.navigate.to v
      begin
        if k == :facebook
          el = @driver.find_element(:css, "a[aria-label='Profile picture'] img")
        else
          binding.pry
          el = @driver.find_element(:css, "header img[class='_8gpiy _r43r5']")
        end
      rescue Selenium::WebDriver::Error::NoSuchElementError
        puts "No #{k} element found fo social link"
      end
      @profile_picture = el['src'] if el
    end
  end

  def ensure_data_with_js
    # check with js/selenium
    @driver = Selenium::WebDriver.for :chrome, switches: %w[--ignore-certificate-errors --disable-translate], driver_path: '/home/durendal/workspace/chromedriver'

    @driver.navigate.to @url

    check_js_loaded_meta_info
    p @meta_info 

    check_js_loaded_social_links
    p @social_links

    check_js_loaded_profile_pic
    p @profile_picture

    @driver.quit
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
      puts uri
      uri.open(redirect: false)
    rescue OpenURI::HTTPRedirect, OpenURI::HTTPError => e
      if e.class == OpenURI::HTTPRedirect
        uri = e.uri
        retry if (tries -= 1) > 0
        raise
      elsif e.class == OpenURI::HTTPError
        puts "404 on #{url}"
        return nil
      end
    end

    Nokogiri::HTML(open(uri))
  end
end

CompaniesScraper.new.scrape

require 'nokogiri'
require 'csv'
require 'open-uri'
require 'selenium-webdriver'
require 'pry'

# For now, scrapes website information based on the following root-level file:
# companylist.csv
class CompaniesScraper
  def initialize
    @source = File.expand_path('../../../companylist.csv', __FILE__)
    @request_handler = RequestHandler.new
    @co_parser = CompaniesParser.new
  end

  def scrape
    CSV.foreach(@source, headers: true) do |row|
      html = @request_handler.page_info(row['URL'])
      name = row['Domain'].match(/(.*)\./)[1]
      @co_parser.parse(html, name) if html
    end
  end

#    pecifically (where b = Brand.new):
#      <meta name="description" content="" /> ----> b.desc
#    <meta property="og:title" content=""> ----> b.name
#    <meta property="og:image" content="" /> ----> b.card_image (this is an url string)
#    (a profile picture from facebook page or instagram page that corresponds to the website) ----> b.profile_image (this is an url string)
end

class CompaniesParser
  META_DESCRIPTION = "meta[name='description']".freeze
  META_TITLE = "meta[property='og:title']".freeze
  META_IMAGE = "meta[property='og:image']".freeze
  FACEBOOK_SELECTOR = 'a[href^="https://www.facebook"]'.freeze
  INSTAGRAM_SELECTOR = 'a[href^="https://www.instagram"]'.freeze

  def parse(html, name)
    @html = html
    @name = name
    @meta_info = {
      description: '',
      title:       '',
      image:       ''
    }
    set_meta_info
    @social_links = {
      facebook:    '',
      instagram:   ''
    }
    set_social_links
    ensure_data_with_js
    # create model
  end

  private

  def set_meta_info
    @meta_info.each do |k, _|
      data = @html.css(self.class.const_get("META_#{k.to_s.upcase}"))[0]
      @meta_info[k] = data['content'] if data
    end
    p @meta_info
  end

  def set_social_links
    @social_links.each do |k, _|
      data = @html.css(self.class.const_get("#{k.to_s.upcase}_SELECTOR") + "[href*='#{@name}']")[0]
      @social_links[k] = data['href'] if data
      p @social_links
    end
  end

  def ensure_data_with_js
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

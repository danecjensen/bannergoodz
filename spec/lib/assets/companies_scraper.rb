require 'spec_helper'

RSpec.describe CompaniesScraper do
  it "should return 'hello' on #hello"
    scraper = CompaniesScraper.new
    expect(scraper.hello).to eq('hello')
  end
end

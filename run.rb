load 'results_crawler.rb'
r = ResultsCrawler.new
r.run





link = "http://www.mylapseventtiming.nl/events/?searchDate=2016-08"
races = {}
filters = r.config.steps.first.filters
f = filters.first
h = f.to_h
page = Nokogiri::HTML(open(link))
elements = page.css(f["container"])
element = elements.first

rr = r.fetch_race_links link, filters
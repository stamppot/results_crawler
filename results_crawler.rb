require 'json'
# OpenStruct is not included by default so you have to add it.
require 'ostruct'
require 'nokogiri'
require 'open-uri'

# class CrawlerConfig

# 	attr_accessor :steps, :output

# end


# class CrawlerStep

# 	attr_accessor :name, :input_links, :filter
# end

class Race

	attr_accessor :name, :race_type, :date, :links, :results, :results_link

	def initialize(name)
		self.name = name
	end
end

class ResultsCrawler

	attr_accessor :config
	attr_accessor :config_file
	# def init(config)
	# 	self.config = config
	# end

	def load
		load_file
		configure
	end

	def load_file(filename = "results_crawler.json")
		puts "Loading cfg file: #{filename}"
		self.config_file = File.read(filename)
		# run(config)
	end
	
	def configure(json_str = nil)
		self.config_file = json_str if json_str
		self.config = JSON.parse(self.config_file, object_class: OpenStruct)
	end

	def run(config_json = self.config)
		# read config
		# puts "cfg: #{config_json.inspect}"
		if config_json.nil?
			puts "No configuration, please load cfg file"
			config_json = load
		end

		first_step_name	= config_json.output
		steps 		= config_json.steps
		first_step = find_step(steps, first_step_name)

		puts "first step: #{first_step_name}"
		links = []
		crawl(steps, first_step)
		puts "results: #{links.inspect}"
		links
	end

	def crawl(steps, start_step)
		output = []

		puts "crawl starting at step: #{start_step.name}"
		# if curr_step.name == start_step
			crawl_rec(steps, start_step, output)
		# end
		puts "output: #{output.inspect}"
	end

	def crawl_rec(steps, curr_step, links = [])
		puts "crawl_rec results: #{links.inspect}"
		puts "curr_step: #{curr_step.inspect}"
		races = {}
		if curr_step.input_links.is_a?(Array)
			# collect links
			puts "crawl_rec: collect links: #{curr_step.input_links.inspect}"
			links = curr_step.input_links

			# get links
			links.each do |link|
				puts "crawl_rec  step: #{curr_step.name} link: #{link.inspect}"
				fetch_race_links(link, f, races)
			end
			# crawl_rec(steps, curr_step, fetched_links)
		else # go to other step 
			# recurse
			puts "step #{curr_step.name}"
			next_step_name = curr_step.input_links
			next_step = find_step(steps, next_step_name)
			races = crawl_rec(steps, next_step, links)

			if fetched_links.any?
				puts "fetched_links: #{fetched_links.inspect}"
			end

		end
		links
	end

	def find_step(steps, stepname)
		steps = steps.select {|step| step.name == stepname }
		steps.any? && steps.first
	end

	# returns [Race(name, type, date, link)]
	# get a list ofobjects with race data and link to more info
	def fetch_race_links(link, filters)
		page = Nokogiri::HTML(open(link))

		races = {}

		found = filters.map do |f| 
			h = f.to_h

			puts "filter: #{f.inspect}"

			elements = page.css(f["container"])

			elements.map do |element|
				# if f.key? "race_type"
				# 	race_type =
				# 	if f["race_type"].start_with? "[" 
				# 		element[f["race_type"]]
				# 	else
				# 		element.css(f["race_type"])
				# 	end
				# end
				date = ""
				if h.key? :race_date
					sel = h[:race_date]
					date = element.css(sel).text
				end

				link = ""
				if h.key? :links
					sel = h[:links]
					link = element.css(sel).first.attributes["href"].value
				end
				puts "link: #{link}"

				if h.key? :race_name
					sel = h[:race_name]
					name = element.css(sel).text

					# add info to already found race, or create race
					race = Race.new(name)
					race.date ||= date # only set if not already set
					race.results_link
					races[name] = race
					puts "found race"
				end
			end
		end
		races
	end

	def example_cfg
		{
			"steps"  =>
				[
					{
						"name" => "step1",
						"input_links" => [
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-06",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-07",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-08",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-09"
						],
						"filters": [
							{
								"container" => "ul.events-list > li",
								"race_type" => "span.tri[title]",
								"race_date" => "time",
								"race_name" => "a.name",
								"links"	    => "a[href]"
							},
							{	"css"  => "span.dua",
								"type" => "['title']"
							}
						]
					},
					{
						"name" => "step2",
						"input_links" => "step1",
						"title" => "h2.entry-title",
						"date" => "h4",
						"filters" => ["Ga naar de uitslagen"]
					},
					{
						"name" => "step3",
						"input_links" => "step2",
						"filters" => ["Overall"]
					}
				],
			"output" => "step3"
		}.to_json
	end
end
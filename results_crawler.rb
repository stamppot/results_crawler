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

	attr_accessor :name, :race_type, :date, :links, :results, :results_link, :status

	def initialize(name)
		self.name = name
	end
end

class ResultsCrawler

	attr_accessor :config
	attr_accessor :config_file
	attr_accessor :races
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
		crawl(steps, first_step, config.output)
		puts "results: #{links.inspect}"
		links
	end

	def crawl(steps, start_step, stop_step)
		output = []

		puts "crawl starting at step: #{start_step.name}"
		# if curr_step.name == start_step
		self.races = crawl_rec(steps, start_step, output)
		steps.shift  # skip first step

		steps.each do |step|
			puts "crawl_races with step: #{step.name}  #{step.inspect}"
			crawl_races(self.races, step, stop_step)
		end
		# end


		puts "output: #{races.inspect}"
	end


	def crawl_races(races, step, stop_step)
		puts "crawl_races step: #{step.name}"
		races = races.map do |name, race|
			fetch_next_link(race, step, stop_step)
		end
		puts "crawl_races DONE step: #{step.name}"
		puts races.inspect
		races
	end

	def crawl_rec(steps, curr_step, links = [])
		puts "crawl_rec results: #{links.inspect}"
		puts "curr_step: #{curr_step.inspect}"
		races = {}

		if curr_step.dependent # go to other step 
			# recurse
			puts "\n step #{curr_step.name}"
			next_step_name = curr_step.dependent
			next_step = find_step(steps, next_step_name)
			puts "before rec crawl_rec curr, next: #{curr_step.name} #{next_step.name}"
			races = crawl_rec(steps, next_step, races)
		elsif curr_step.input_links
			# collect links
			puts "crawl_rec: collect links: #{curr_step.input_links.inspect}"
			links = curr_step.input_links
			action = curr_step.action

			# get links
			links.each do |link|
				puts "crawl_rec  curr: #{curr_step.name}  action: #{action} link: #{link.inspect}"
				self.send(action, link, curr_step, races)  # fetch page links
			end
		end
		races
	end

	def find_step(steps, stepname)
		steps = steps.select {|step| step.name == stepname }
		steps.any? && steps.first
	end

	def fetch_next_link(race, curr_step, stop_step)
		links = []

		puts "fetch_next_link race: step: #{curr_step}.name  #{race.inspect}"
		visit_links = race.results_link

		return race if curr_step.name == stop_step

		race.results_link = []
		visit_links.each do |link|
			page = Nokogiri::HTML(open(link))
	
			puts "fetch_next_links: #{link} "
			
			filter = curr_step.filters.first
			puts "filter: #{filter.inspect}"
			h = filter.to_h
		
			elements = page.css(h[:container])
	
			elements.map do |element|
				date = ""
	
				next_link = ""
				if h.key? :links
					sel = h[:links]
					puts "selector: #{sel}"
					elem = element.css(sel)
					if elem.nil? || elem.empty?
						puts "No link to results found, skipping"
						race.status = :failed
						next
					end

					puts "elem: #{elem.inspect}"
					next_link = elem.first.attributes["href"].value
					puts "fetch_next_link FOUND #{next_link}"
				end
				# puts "link: #{link}"
	
				name = race.name
				if h.key? :race_name
					sel = h[:race_name]
					name = element.css(sel).text
					puts "race_name: #{name}"
					# add info to already found race, or create race
					race.date ||= date # only set if not already set
				end
				
				if !next_link.empty?
					race.results_link = []
					race.results_link << next_link
					# races[name] = race
					puts "LAST step: #{next_link} race: #{race.inspect}"
					puts "found race #{name}  next_link: #{next_link}  results_link: #{race.results_link}"
				end

			end
		end
		race
	end

	# returns [Race(name, type, date, link)]
	# get a list ofobjects with race data and link to more info
	def fetch_race_links(link, curr_step, races = {})
		page = Nokogiri::HTML(open(link))

		filters = curr_step.filters
		puts "fetch race_links: #{races.size}"
		found = filters.map do |f| 
			h = f.to_h

			puts "filter: #{f.inspect}"

			elements = page.css(f["container"])

			elements.map do |element|
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
				# puts "link: #{link}"

				if h.key? :race_name
					sel = h[:race_name]
					name = element.css(sel).text

					# add info to already found race, or create race
					race = races[name] || Race.new(name)
					race.date ||= date # only set if not already set
					race.results_link ||= []
					race.results_link << link
					races[name] = race
					puts "found race #{name}  results_link: #{race.results_link}"
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
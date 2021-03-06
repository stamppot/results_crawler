# encoding: utf-8

require 'json'
# OpenStruct is not included by default so you have to add it.
require 'ostruct'
require 'nokogiri'
require 'open-uri'
require 'csv'

require 'iconv' unless String.method_defined?(:encode)
# class CrawlerConfig

# 	attr_accessor :steps, :output

# end


# class CrawlerStep

# 	attr_accessor :name, :input_links, :filter
# end

class Race

	attr_accessor :name, :race_type, :date, :links, :results, :results_link, :status, :result_pages
	attr_accessor :race_results  # hash of category -> [RaceResults]

	def initialize(name)
		self.name = name
		self.race_results = {}
	end
end

class RaceResult
	attr_accessor :race_name, :race_date, :race_type, :person_name, :category, :results

	def pretty
		times = results.map {|r| "#{r.first}: #{r.last}"}.join("\t")
		"#{race_name} (#{category}: #{times}"
	end

end

class ResultsCrawler
	attr_accessor :config
	attr_accessor :config_file
	attr_accessor :races
	attr_accessor :participants_list
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

	def participants
		self.participants_list
	end

	def participants=(csv_file)
		self.participants_list = CSV.read(csv_file, :headers => true).to_a.flatten[1..-1]
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

	def by_race(race_results)
		by_race = race_results.inject({}) do |h, r|
			h[r.race_name] = []
			h[r.race_name] << r
			h
		end
	end


	def by_person(race_results)
		by_person = race_results.inject({}) do |h, r|
			h[r.person_name] = []
			h[r.person_name] << r
			h
		end
	end

	def to_html(grouped_results)
		html = ["<table>"]
		grouped_results.each do |race, results|

			html << "<tr></tr>"

			if results.any?  # add header
				html << "<tr>" 

				# TODO : add category and date
				results.first.results.keys.each do |header|
					html << "<th>#{header}</th>"
				end
				html << "</tr>" 
			end

			results.each do |result|
				html << "<tr>" 

				puts "result.results: #{result.results.inspect}"
				result.results.values.each do |r|
					html << "<td>" << r << "</td>"
				end
				html << "</tr>" 
			end
		end

		html << "</table>"
		html
	end


	def get_results # for participants, find better name
		self.run if self.races.nil?

		if participants.nil?
			puts "Missing list of people. self.participants = <csvfilename>"
		end
		people = participants

		race_results = []

		# TODO: quick sort these by name, find persons by bsearch 
		self.races.values.each do |race|

			race.race_results.each do |category, results|

				participants.each do |person|
					found = results.select {|res| res["Naam"] == person }
					if found.any?
						rr = RaceResult.new
						rr.race_name = race.name
						rr.race_date = race.date
						rr.race_type = race.race_type
						rr.person_name = person
						rr.category = category
						rr.results = found.first
						race_results << rr
						puts "found: #{rr.inspect}"
					end
				end
			end
		end
		race_results
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

		overview_pages = fetch_race_categories_links(races, steps.last)
		# puts "overview pages: #{overview_pages.class} #{overview_pages.inspect}"
		found_links, missing_links  = overview_pages.compact.partition {|h| !h.nil? && !h.empty? }

		# puts "output: #{races.inspect}"

		fetch_result_pages self.races, true

		# find names in list
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

	def find_results_for_persons(persons)


	end

	def fetch_result_pages(races, write_csv_output = nil)

		outputfolder = "output"
		if write_csv_output
			Dir.mkdir(outputfolder) if !Dir.exists?(outputfolder)
		end

		races.each do |name, race|

			results = {}
			race.result_pages ||= {}
			race.result_pages.each do |category, link|
				puts "link: #{link.inspect}"
				filename, page = load_or_fetch_page(link)
				puts "filename: #{filename}"
				race_date = get_date_from_link(link)
				csv_hashes = results_page_parser(page, race_date) 

				if write_csv_output && csv_hashes.any?
					headers = csv_hashes.first.keys
					csv_lines = csv_hashes.map {|h| h.values }

					file = filename.gsub(".html", "")
					puts "input file: #{filename}, output file: #{file}"
					output_file = "#{outputfolder}/#{file}.csv"
					CSV.open(output_file, "wb") do |csv|
						csv << headers
						csv_lines.each {|line| csv << line}
    			  	end
		    	end

				results[category] = csv_hashes
			end
			race.race_results = results
		end
	end

	def get_date_from_link(link)
		find_date = link.scan(/\d+.*/).first
		find_date = find_date.gsub("_", "") if find_date
		dt = Date.new(1999)
		begin
			dt = Date.parse find_date
		rescue
		end
		dt
	end

	def results_page_parser(page, race_date_arg = nil)
		csv = []
		# csv.to_a.map {|row| row.to_hash }

		html_object = Nokogiri::HTML(page)
		race_info = html_object.css('table tr td.REPORTHEADER').map {|head| head.text }
		race_name = ""
		race_date = ""
		if race_date_arg
			race_date = race_date_arg.strftime("%F")
			puts "got race_date_from_link: #{race_date}"
		end

		if race_info.any?
			info = race_info.first.encode("UTF-16be", :invalid=>:replace, :replace=>"").encode('UTF-8').split("|")  # info is usually split with '|' but not always
			race_name = info.first
			race_date_str = info.last
			puts "race_date_str: #{race_date_str}"
			begin
				race_date_dd = race_date_str.length >= 8 && Date.parse(race_date_str)
			rescue ArgumentError
				race_date_dd = race_date_arg
			end
			puts "got race date from html table header: #{race_date_dd.strftime('%F')}"
			arg_is_valid_date_but_wrong = race_date_arg && race_date_arg.is_a?(Date) && race_date && race_date_arg.year > race_date_dd.year
			if arg_is_valid_date_but_wrong || !race_date_arg.is_a?(Date)
				race_date = race_date_dd.strftime("%F") if race_date.is_a?(Date)
			end
		end
		puts "race_info: #{race_info.inspect} name: #{race_name}, date: #{race_date}, race_date_arg: #{race_date_arg.inspect}"
		
		headers = html_object.css('table tr th.FIELDNAMES').map {|head| head.text }
		headers << "race" << "date"
		header_size = headers.size
		# puts "HEADERS: #{headers.inspect}"
		html_object.css('table tr').each do |row|
	  		tarray = [] 
  			row.xpath('td').each do |cell|
    			tarray << cell.text.encode("UTF-16be", :invalid=>:replace, :replace=>"").encode('UTF-8')
	  		end
	  		tarray << race_name << race_date
	  		puts "tarray: #{tarray.inspect}"
	  		next if tarray.size != header_size
  			csv << tarray
		end

		# puts "CSV output:\n#{csv}"
		# puts "csv_str: #{csv_str}"		

		csv_hashes = csv.map {|row| headers.zip(row).to_h }
		puts "csv_hashes: #{csv_hashes.inspect}"
		csv_hashes
	end

	def fetch_race_categories_links(races, step)
		puts "fetch_race_categories_links"
		filters = step.filters


		races.values.map do |race|
			puts "race: #{race.inspect}"
			found_links = {}
			next if race.results_link.empty?

			link = race.results_link.select {|l| !l.include?("@") }.first

			split_path = link.split("/")[0...-1]
			absolute_path = split_path.join("/")
			puts "absolute path: #{absolute_path}"

			filename, p = load_or_fetch_page(link)
			page = Nokogiri::HTML(p)

			puts "fetch race_links: #{races.size}"
			filters.each do |f| 
				h = f.to_h
	
				puts "filter: #{f.inspect}"
	
				elements = page.css(f["container"])
	
				elements.each do |element|
					link = ""
					if h.key? :links
						sel = h[:links]
						elems = element.css(sel)
						elems.map do |elem|
							if elem.attributes["href"].nil?
								"No links found: #{elem.inspect}"
								next
							end

							if elem.attributes["href"].count > 1
								puts "DOUBLE attributes: #{elem.attributes["href"].value}"
								elem = elem.attributes["href"].select {|at| !at.value.contains("@") }
							end
							link = elem.attributes["href"].value.strip.encode("UTF-16be", :invalid=>:replace, :replace=>"").encode('UTF-8')
							text = elem.text.encode("UTF-16be", :invalid=>:replace, :replace=>"").encode('UTF-8')
							# puts "text: #{text} : #{link}"
							if !link.start_with? "http"
								link = fix_link_path(absolute_path, link)
								# puts "full link: #{link}"
							end
					
							if h.key? :regex
								regex = h[:regex]
								# puts "regex: #{regex}"

								if text =~ /#{regex}/
									puts "INCLUDE link: #{text} #{link}\n\n"
									found_links[text] = link
								else
									puts "skip link: #{text}\n\n"
								end
							end
						end
					end
				end
			end
			race.result_pages = found_links
			found_links
		end
	end

	def load_or_fetch_page(link)
		dir = Dir.pwd + "/cache"  # TODO: move this check to beginning of run method
		Dir.mkdir(dir) if !File.exist? dir

		filename = link_to_filename(link)
		path = dir + "/" + filename
		puts "load from: #{path}"

		data = ""
		if File.exist?(path)
			puts "File exists: #{path}"
			data = File.read(path)
		else
			# get and save file
			begin
				open(link) { |io| data = io.read }
			rescue OpenURI::HTTPError => error
				response = error.io
				response.status
				response.string
				puts "Error: #{response.status}  #{response.string} url: #{link}"
				return ""
			rescue URI::InvalidURIError
				return ""
			end
			# puts "read url: #{data}"

			open(path, 'w') do |f|
  				f << data
			end
			# IO.write(data, path)
		end

		if String.method_defined?(:encode)
			data.encode!('UTF-8', 'UTF-8', :invalid => :replace, :replace => "O")
		else
			ic = Iconv.new('UTF-8', 'UTF-8//IGNORE')
			data = ic.iconv(file_contents)
		end

		[filename, data] # return filename and page data
	end

	def link_to_filename(link)
		link.gsub("http://", "").gsub("nl.mylaps.com/evenementen/uitslagen/", "").gsub("/", "-")
	end

	# def filename_to_link(filename)
	# 	"http://" + filename.gsub("_-_", "/")
	# end

	def fix_link_path(absolute_path, link)
		absolute_path += "/" if !absolute_path.end_with?("/") && !link.start_with?("/")
		absolute_path + link
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
				self.send(action, link, curr_step, races)  # fetch race links
			end
		end
		races
	end

	def write(path, data)
		data = data.join if data.is_a?(Array)
		open(path, 'w') do |f|
			f << data
		end
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
			filename, page = load_or_fetch_page(link)
			page = Nokogiri::HTML(page)
	
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

					# puts "elem: #{elem.inspect}"
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
					puts "race_date: #{race.date}"
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
		filename, data = load_or_fetch_page(link)
		page = Nokogiri::HTML(data)

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
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-01",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-02",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-03",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-04",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-05",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-06",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-07",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-08",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-09",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-10",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-11",
							"http =>//www.mylapseventtiming.nl/events/?searchDate=2016-12"
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
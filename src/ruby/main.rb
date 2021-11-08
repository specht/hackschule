require 'sinatra/base'
require 'faye/websocket'
require 'json'
require 'date'
require 'kramdown'
require 'neography'
require 'open3'
require 'timeout'
require 'yaml'
require 'mail'
require 'net/imap'
require 'set'
require 'digest/sha1'
require 'htmlentities'
require '/credentials.rb'
require 'mysql2'
require 'digest/sha2'

WEEK_DAYS = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']

DEVELOPMENT = ENV['DEVELOPMENT']

def update_resolutions(use_tag = nil)
    tags = []
    if use_tag.nil?
        tags = Dir['/raw/uploads/*.png'].sort.map { |x| File.basename(x).sub('.png', '') }
        STDERR.puts "Refreshing generated images..."
    else
        tags = [use_tag]
    end
    tags.each do |tag|
        original_path = "/raw/uploads/#{tag}.png"
        [300, 150, 128, 64, 48, 24].each do |width|
            png_path = File.join("/gen/#{tag}-#{width}.png")
            unless File.exists?(png_path)
                STDERR.puts png_path
                system("convert \"#{original_path}\" -resize #{width}x#{width}^\\> -strip \"#{png_path}\"")
            end
        end
    end
end

Neography.configure do |config|
    config.protocol             = "http"
    config.server               = "neo4j"
    config.port                 = 7474
    config.directory            = ""  # prefix this path with '/'
    config.cypher_path          = "/cypher"
    config.gremlin_path         = "/ext/GremlinPlugin/graphdb/execute_script"
    config.log_file             = "/dev/shm/neography.log"
    config.log_enabled          = false
    config.slow_log_threshold   = 0    # time in ms for query logging
    config.max_threads          = 20
    config.authentication       = nil  # 'basic' or 'digest'
    config.username             = nil
    config.password             = nil
    config.parser               = MultiJsonParser
    config.http_send_timeout    = 1200
    config.http_receive_timeout = 1200
    config.persistent           = true
end

module QtsNeo4j

    class CypherError < StandardError
        def initialize(code, message)
            @code = code
            @message = message
        end
        
        def to_s
            "Cypher Error\n#{@code}\n#{@message}"
        end
    end

    def transaction(&block)
        @neo4j ||= Neography::Rest.new
        @tx ||= []
        @tx << (@tx.empty? ? @neo4j.begin_transaction : nil)
        begin
            result = yield
            item = @tx.pop
            unless item.nil?
                @neo4j.commit_transaction(item)
            end
            result
        rescue
            item = @tx.pop
            unless item.nil?
                begin
                    @neo4j.rollback_transaction(item)
                rescue
                end
            end
            raise
        end
    end

    class ResultRow
        def initialize(v)
            @v = Hash[v.map { |k, v| [k.to_sym, v] }]
        end

        def props
            @v
        end
    end

    def neo4j_query(query_str, options = {})
        transaction do
            temp_result = @neo4j.in_transaction(@tx.first, [query_str, options])
            if temp_result['errors'] && !temp_result['errors'].empty?
                STDERR.puts "This:"
                STDERR.puts temp_result.to_yaml
                raise CypherError.new(temp_result['errors'].first['code'], temp_result['errors'].first['message'])
            end
            result = []
            temp_result['results'].first['data'].each_with_index do |row, row_index|
                result << {}
                temp_result['results'].first['columns'].each_with_index do |key, key_index|
                    if row['row'][key_index].is_a? Hash
                        result.last[key] = ResultRow.new(row['row'][key_index])
                    else
                        result.last[key] = row['row'][key_index]
                    end
                end
            end
            result
        end
    end

    def neo4j_query_expect_one(query_str, options = {})
        transaction do
            result = neo4j_query(query_str, options).to_a
            unless result.size == 1
                STDERR.puts '-' * 40
                STDERR.puts query_str
                STDERR.puts options.to_json
                STDERR.puts '-' * 40
                raise "Expected one result but got #{result.size}"
            end
            result.first
        end
    end
end

class Neo4jGlobal
    include QtsNeo4j
end

$neo4j = Neo4jGlobal.new

class RandomTag
    BASE_31_ALPHABET = '0123456789bcdfghjklmnpqrstvwxyz'
    def self.to_base31(i)
        result = ''
        while i > 0
            result += BASE_31_ALPHABET[i % 31]
            i /= 31
        end
        result
    end

    def self.generate(length = 12)
        self.to_base31(SecureRandom.hex(length).to_i(16))[0, length]
    end
end    

def mail_html_to_plain_text(s)
    s.gsub('<p>', "\n\n").gsub(/<br\s*\/?>/, "\n").gsub(/<\/?[^>]*>/, '').strip
end

def deliver_mail(&block)
    mail = Mail.new do
        self.instance_eval(&block)
    end
    if DEVELOPMENT
        STDERR.puts "Not sending e-mail in development mode:"
        STDERR.puts mail.to_s
    else
        mail.deliver!
    end

#     mail.subject("[WEB] #{mail.subject}")
# 
#     # also store a copy in a special folder
#     target_mailbox = 'Sent from Web'
#     imap = Net::IMAP.new(IMAP_SERVER, :ssl => true)
#     imap.authenticate('PLAIN', SMTP_USER, SMTP_PASSWORD)
#     imap.create(target_mailbox) unless imap.list('', target_mailbox)
#     imap.select(target_mailbox)
#     imap.append(target_mailbox, mail.to_s.gsub(/(\r?)\n/, "\r\n"))
#     imap.logout
#     imap.disconnect
end

def parse_markdown(s)
    s ||= ''
    Kramdown::Document.new(s, :smart_quotes => %w{sbquo lsquo bdquo ldquo}).to_html.strip
end

class SetupDatabase
    include QtsNeo4j
    
    def setup
        delay = 1
        10.times do
            begin
                transaction do
                    STDERR.puts "Removing all constraints and indexes..."
                    indexes = []
                    neo4j_query("CALL db.constraints").each do |constraint|
                        query = "DROP #{constraint['description']}"
                        neo4j_query(query)
                    end
                    neo4j_query("CALL db.indexes").each do |index|
                        query = "DROP #{index['description']}"
                        neo4j_query(query)
                    end
                    
                    STDERR.puts "Setting up constraints and indexes..."
                    neo4j_query("CREATE CONSTRAINT ON (n:User) ASSERT n.email IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Task) ASSERT n.slug IS UNIQUE")
                    neo4j_query("CREATE CONSTRAINT ON (n:Script) ASSERT n.sha1 IS UNIQUE")
                    neo4j_query("CREATE INDEX ON :Submission(correct)")
                    neo4j_query("CREATE INDEX ON :Submission(t0)")
                end
                transaction do
                    # give admin rights to admin
                    ADMIN_MAIL_ADDRESSES.each do |email|
                        neo4j_query(<<~END_OF_QUERY, :email => email)
                            MATCH (u:User {email: {email}})
                            SET u.admin = true;
                        END_OF_QUERY
                    end
                    # add file sizes and line counts for script nodes without them
                    fix_these_scripts = neo4j_query(<<~END_OF_QUERY)
                        MATCH (sc:Script)
                        WHERE sc.size IS NULL OR sc.lines IS NULL
                        RETURN sc.sha1 AS sha1;
                    END_OF_QUERY
                    fix_these_scripts.each do |entry|
                        sha1 = entry['sha1']
                        script = File.read("/raw/code/#{sha1}.py")
                        size = script.size
                        lines = script.count("\n") + 1
                        neo4j_query(<<~END_OF_QUERY, {:sha1 => sha1, :size => size, :lines => lines})
                            MATCH (sc:Script {sha1: {sha1}})
                            SET sc.size = {size}, sc.lines = {lines};
                        END_OF_QUERY
                        STDERR.puts "#{sha1} #{size} #{lines}"
                    end
                end
                
                update_resolutions()
                    
                STDERR.puts "Setup finished."
                
                break
            rescue
                STDERR.puts $!
                STDERR.puts "Retrying setup after #{delay} seconds..."
                sleep delay
                delay += 1
            end
        end
    end
end

class Main < Sinatra::Base
    include QtsNeo4j
    
#     error RuntimeError do
# #         respond(:error => env['sinatra.error'])
#         redirect "#{WEB_ROOT}/", 302
#     end
    
    def self.task_link(slug)
        task = @@tasks[slug]
        "<a href='/task/#{task[:slug]}'>#{task[:title]}</a>"
    end
    
    def self.load_tasks
        STDERR.puts "Refreshing tasks..."
        @@cat_config = {}
        @@tasks = {}
        cat_slug_for_cat_title = {}
        Dir['/tasks/**/*.txt'].sort.each do |path|
            next unless File.file?(path)
            if File.basename(path) == 'config.txt'
                parts = path.sub('/tasks/', '').split('/')
                cat = parts[0]
                cat.sub!(/^\d+/, '')
                cat.strip!
#                 STDERR.puts "Loading #{path}..."
                parts = File.read(path).split('-' * 8)
                cat_info = {:config => YAML::load(parts[0]) || {}, 
                            :teaser => parse_markdown(parts[1]),
                            :description => parse_markdown(parts[2]),
                            :title => cat}
                @@cat_config[cat_info[:config]['cat_slug']] = cat_info
                cat_slug_for_cat_title[cat] = cat_info[:config]['cat_slug']
            else
                parts = path.sub('/tasks/', '').split('/')
                cat = parts[0]
                slug = parts[1]
                cat_index = cat.to_i
                cat.sub!(/^\d+/, '')
                cat.strip!
                @@cat_order[cat] = cat_index
                task = {}
                task[:dir] = File::dirname(path)
                task[:cat] = cat
                task[:count_score] = true
                task[:order] = slug.to_i
                task[:slug] = slug.sub(/^\d+(\-)?/, '').sub(/\.txt$/, '').strip
                read_this = false
                if @@tasks.include?(task[:slug])
                    raise "Duplicate task slug: #{task[:slug]}"
                end
                parts = File.read(path).split('-' * 8)
                task.merge!(Hash[YAML::load(parts.shift.strip).map {|k, v| [k.to_sym, v]}])
                s = parts.shift.strip
                task[:description] = parse_markdown(s)
                task[:hints] = []
                if task[:target_image]
                    task[:target_image] = JSON.parse(File.read(File.join('/planets', task[:target_image])))
                    task[:target_image] = Hash[task[:target_image].map { |k, v| [k.to_sym, v] }]
                end

                task[:custom_import_main] = 'from main import *'
                parts.reject! do |part|
                    if part.strip.index('[verify]') == 0
                        task[:verify] = part.sub('[verify]', '').strip
                        true
                    elsif part.strip.index('[template]') == 0
                        task[:template] = part.sub('[template]', '').strip
                        true
                    elsif part.strip.index('[input]') == 0
                        task[:input] = part.sub('[input]', '').strip
                        true
                    elsif part.strip.index('[custom_pre]') == 0
                        task[:custom_pre] = part.sub('[custom_pre]', '').strip
                        true
                    elsif part.strip.index('[custom_file') == 0
                        task[:custom_files] ||= {}
                        cfpath = part.strip.match(/\[custom_file\s+(.+)\]/)[1]
                        lines = part.strip.split("\n")
                        lines = lines[1, lines.size - 1]
                        task[:custom_files][cfpath] = lines.join("\n")
                        true
                    elsif part.strip.index('[custom_post]') == 0
                        task[:custom_post] = part.sub('[custom_post]', '').strip
                        true
                    elsif part.strip.index('[custom_import_main]') == 0
                        task[:custom_import_main] = part.sub('[custom_import_main]', '').strip
                        true
                    elsif part.strip.index('[dungeon_init]') == 0
                        task[:dungeon_init] = part.sub('[dungeon_init]', '').strip
                        true
                    elsif part.strip.index('[map]') == 0
                        task[:map] = part.sub('[map]', '').strip
                        true
                    elsif part.strip.index('[hint]') == 0
                        s = part.sub('[hint]', '').strip
                        while true
                            index = s.index('#{')
                            break if index.nil?
                            length = 2
                            balance = 1
                            while index + length < s.size && balance > 0
                                c = s[index + length]
                                balance -= 1 if c == '}'
                                balance += 1 if c == '{'
                                length += 1
                            end
                            code = s[index + 2, length - 3]
                            begin
                                s[index, length] = eval(code).to_s || ''
                            rescue
                                STDERR.puts "Error while evaluating:"
                                STDERR.puts code
                                raise
                            end
                        end
                        task[:hints] << parse_markdown(s)
                        true
                    else
                        false
                    end
                end
                task[:template] ||= ''
                capture = task[:template].match(/def\s+([^\(:]+)/)
                if capture
                    task[:function_name] = capture[1]
                end
                task[:function_name] ||= 'solve'
                task[:mtime] = File::mtime(path)
                @@tasks[task[:slug]] = task
            end
        end
        @@tasks.keys.each do |slug|
            task = @@tasks[slug]
            @@cat_config[cat_slug_for_cat_title[task[:cat]]][:config].each do |k, v|
                unless k == 'description'
                    task[k.to_sym] ||= v
                end
            end
            @@tasks[slug] = task
        end
        
        @@cats_sorted = @@cat_order.keys.sort do |a, b|
            @@cat_order[a] <=> @@cat_order[b]
        end
        @@task_keys_sorted = @@tasks.keys.sort do |a, b|
            task_a = @@tasks[a]
            task_b = @@tasks[b]
            cat_a = task_a[:cat]
            cat_b = task_b[:cat]
            if @@cat_order[cat_a] == @@cat_order[cat_b]
                task_a[:order] <=> task_b[:order]
            else
                @@cat_order[cat_a] <=> @@cat_order[cat_b]
            end
        end
        @@cat_info = {}
        @@task_keys_sorted.each do |k|
            task = @@tasks[k]
            @@cat_info[task[:cat]] ||= []
            @@cat_info[task[:cat]] << k
        end
    end
    
    def self.load_invitations
        @@invitations = {}
        @@user_groups = {}
        current_group = '(keine Gruppe)'
        group_admins = {}
        used_mysql_logins = Set.new()
        File.open('invitations.txt') do |f|
            f.each_line do |line|
                next if line.strip.empty?
                next if line.strip[0] == '#'
                if line[0] == '>'
                    current_group = line[1, line.size - 1].strip
                    group_admins[current_group] ||= Set.new()
                    ADMIN_MAIL_ADDRESSES.each do |email|
                        group_admins[current_group] << email
                    end
                elsif line[0] == '+'
                    group_admins[current_group] << line[1, line.size - 1].strip.delete_prefix('<').delete_suffix('>')
                else
                    gender = line[0]
                    gender = 'all' if gender == 'x'
                    parts = line[1, line.size - 1].strip.split(' ')
                    email = parts.last.delete_prefix('<').delete_suffix('>').downcase
                    @@user_groups[current_group] ||= Set.new()
                    @@user_groups[current_group] << email
                    mysql_user = email.split('@').first[0, 30]
                    i = 0
                    while used_mysql_logins.include?(mysql_user)
                        i += 1
                        mysql_user = "#{email.split('@').first[0, 30]}#{i}"
                    end
                    used_mysql_logins << mysql_user
                    @@invitations[email] = {:gender => gender,
                                            :group => current_group,
                                            :mysql_user => mysql_user,
                                            :mysql_password => self.gen_password_for_email(email, MYSQL_PASSWORD_SALT)}
                    if parts.size > 1
                        name = parts[0, parts.size - 1].join(' ')
                        @@invitations[email][:name] = name
                    end
                end
            end
        end
        @@teachers = {}
        group_admins.each_pair do |group, emails|
            emails.each do |email|
                @@teachers[email] ||= Set.new()
                @@teachers[email] << group
            end
        end
        @@lego_icons = {:m => [], :w => [], :all => []}
        File.open('lego-icons.txt') do |f|
            f.each_line do |line|
                line.strip!
                gender = nil
                if line =~ /^[mw]\s/
                    gender = line[0]
                    line = line[1, line.size - 1].strip
                    @@lego_icons[gender.to_sym] << line
                end
                @@lego_icons[:all] << line
            end
        end
    end
                                   
    def self.gen_password_for_email(email, salt)
        chars = 'BCDFGHJKMNPQRSTVWXYZ23456789'.split('')
        sha2 = Digest::SHA256.new()
        sha2 << salt
        sha2 << email
        srand(sha2.hexdigest.to_i(16))
        password = ''
        8.times do 
            c = chars.sample.dup
            c.downcase! if [0, 1].sample == 1
            password += c
        end
        password += '-'
        4.times do 
            c = chars.sample.dup
            c.downcase! if [0, 1].sample == 1
            password += c
        end
        password
    end
    
    configure do
        set :show_exceptions, false
    end
    
    configure do
        @@compiled_files = {}
        @@cat_order = {}
        @@tasks = {}
        @@invitations = Hash.new()
        @@lego_icons = Hash.new
        self.load_tasks
        self.load_invitations
        setup = SetupDatabase.new()
        setup.setup()
        STDERR.puts $0
        exit
        if ENV['HACKSCHULE_SERVICE'] == 'ruby'
            delay = 1
            # unless DEVELOPMENT
                10.times do
                    begin
                        client = Mysql2::Client.new(:host => "mysql", :username => "root", :password => MYSQL_ROOT_PASSWORD)
                        @@invitations.keys.each do |email|
                            user = @@invitations[email][:mysql_user]
                            password = @@invitations[email][:mysql_password]
                            ["CREATE USER IF NOT EXISTS '#{user}'@'%' identified by '#{password}';",
                            "CREATE DATABASE IF NOT EXISTS `#{user}`;",
                            "GRANT ALL ON `#{user}`.* TO '#{user}'@'%';",           
                            ].each do |query|
                                STDERR.puts query
                                client.query(query)
                            end
                        end
                        client.query('FLUSH PRIVILEGES;')
                        break
                    rescue Mysql2::Error::ConnectionError => e
                        STDERR.puts "Can't connect to MySQL, retrying in #{delay} seconds..."
                        sleep delay
                        delay += 1
                    end
                end
            # end
            STDERR.puts "Server is up and running!"
        end
    end
    
    def assert(condition, message = 'assertion failed')
        raise message unless condition
    end

    def test_request_parameter(data, key, options)
        type = ((options[:types] || {})[key]) || String
        assert(data[key.to_s].is_a?(type), "#{key.to_s} is a #{type}")
        if type == String
            assert(data[key.to_s].size <= (options[:max_value_lengths][key] || options[:max_string_length]), 'too_much_data')
        end
    end
    
    def parse_request_data(options = {})
        options[:max_body_length] ||= 512
        options[:max_string_length] ||= 512
        options[:required_keys] ||= []
        options[:optional_keys] ||= []
        options[:max_value_lengths] ||= {}
        data_str = request.body.read(options[:max_body_length]).to_s
        @latest_request_body = data_str.dup
        begin
            assert(data_str.is_a? String)
            assert(data_str.size < options[:max_body_length], 'too_much_data')
            data = JSON::parse(data_str)
            @latest_request_body_parsed = data.dup
            result = {}
            options[:required_keys].each do |key|
                assert(data.include?(key.to_s))
                test_request_parameter(data, key, options)
                result[key.to_sym] = data[key.to_s]
            end
            options[:optional_keys].each do |key|
                if data.include?(key.to_s)
                    test_request_parameter(data, key, options)
                    result[key.to_sym] = data[key.to_s]
                end
            end
            result
        rescue
            STDERR.puts "Request was:"
            STDERR.puts data_str
            raise
        end
    end
    
    def user_logged_in?
        !@session_user.nil?
    end
    
    def admin_logged_in?
        @session_user && @session_user[:admin]
    end
    
    def teacher_logged_in?
        @session_user && @@teachers.include?(@session_user[:email])
    end
    
    def this_user_logged_in?(login)
        @session_user && (@session_user[:login] == login)
    end
    
    def this_user_or_admin_logged_in?(login)
        admin_logged_in? || this_user_logged_in?(login)
    end
    
    def require_user!
        assert(user_logged_in?)
    end
    
    def require_admin!
        assert(admin_logged_in?)
    end
    
    def require_teacher!
        assert(teacher_logged_in?)
    end
    
    def require_this_user_or_admin(login)
        assert(this_user_or_admin_logged_in?(login))
    end
    
    def require_this_user(login)
        assert(this_user_logged_in?(login))
    end
    
    def this_is_a_page_for_logged_in_users
        unless user_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    def this_is_a_page_for_logged_in_admins
        unless admin_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    def this_is_a_page_for_logged_in_teachers
        unless teacher_logged_in?
            redirect "#{WEB_ROOT}/", 303
        end
    end
    
    def all_sessions
        sids = request.cookies['sid']
        users = []
        if (sids.is_a? String) && (sids =~ /^[0-9A-Za-z,]+$/)
            sids.split(',').each do |sid|
                if sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => sid).map { |x| {:sid => x['sid'], :user => x['user'].props } }
                        MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
                        RETURN s.sid AS sid, u AS user;
                    END_OF_QUERY
                    results.each do |entry|
                        users << entry
                    end
                end
            end
        end
        users
    end
    
    def purge_missing_sessions
        sid = request.cookies['sid']
        existing_sids = []
        if (sid.is_a? String) && (sid =~ /^[0-9A-Za-z,]+$/)
            sids = sid.split(',')
            sids.each do |sid|
                if sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => sid).map { |x| x['sid'] }
                        MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
                        RETURN s.sid AS sid;
                    END_OF_QUERY
                    existing_sids << sid unless results.empty?
                end
            end
        end
        existing_sids.join(',')
    end
    
    before '*' do
        if DEVELOPMENT
            self.class.load_tasks
        end
        @latest_request_body = nil
        @latest_request_body_parsed = nil
        # before any API request, determine currently logged in user via the provided session ID
        @session_user = nil
        @session_user_impersonated = nil
        if request.cookies.include?('sid')
            sid = request.cookies['sid']
            if (sid.is_a? String) && (sid =~ /^[0-9A-Za-z,]+$/)
                first_sid = sid.split(',').first
                if first_sid =~ /^[0-9A-Za-z]+$/
                    results = neo4j_query(<<~END_OF_QUERY, :sid => first_sid).to_a
                        MATCH (s:Session {sid: {sid}})-[:BELONGS_TO]->(u:User)
                        RETURN s, u;
                    END_OF_QUERY
                    if results.size == 1
                        session_expiry = results.first['s'].props[:expires]
                        if DateTime.parse(session_expiry) > DateTime.now
                            @session_user = results.first['u'].props.reject {|k, v| k == :password }
                            email = @session_user[:email]
                            [:mysql_user, :mysql_password].each do |k|
                                @session_user[k] = @@invitations[email][k]
                            end
                        end
                    end
                end
            end
        end
    end
    
    after '/api/*' do
        if @respond_content
            response.body = @respond_content
            response.headers['Content-Type'] = @respond_mimetype
        else
            @respond_hash ||= {}
            response.body = @respond_hash.to_json
        end
    end
    
    def respond(hash = {})
        @respond_hash = hash
    end
    
    def respond_raw_with_mimetype(content, mimetype)
        @respond_content = content
        @respond_mimetype = mimetype
    end
    
    @@clients = {}
    
    def htmlentities(s)
        @html_entities_coder ||= HTMLEntities.new
        @html_entities_coder.encode(s)
    end
    
    def store_script(script)
        require_user!
        script = script.rstrip + "\n"
        script_sha1 = RandomTag::to_base31(Digest::SHA1.hexdigest(script).to_i(16))[0, 8]
        script_path = "/raw/code/#{script_sha1}.py"
        unless File.exists?(script_path)
            File.open(script_path, 'w') { |f| f.write(script) }
            neo4j_query(<<~END_OF_QUERY, :sha1 => script_sha1, :size => script.size, :lines => script.count("\n") + 1)
                MERGE (sc:Script {sha1: {sha1}, size: {size}, lines: {lines}})
            END_OF_QUERY
        end
        return script_sha1, script
    end
    
    get '/ws' do
        require_user!
        if Faye::WebSocket.websocket?(request.env)
            ws = Faye::WebSocket.new(request.env)
            
            ws.on(:open) do |event|
                ws.send({:hello => 'world', :rate_limit => RATE_LIMIT}.to_json)
            end

            ws.on(:close) do |event|
            end

            ws.on(:message) do |msg|
                client_id = request.env['HTTP_SEC_WEBSOCKET_KEY']
                begin
                    request = {}
                    unless msg.data.empty?
                        request = JSON.parse(msg.data)
                    end
                    if request['action'] == 'run'
                        task = @@tasks[request['slug']]
                        unless task.nil?
                            fifo = nil
                            
                            script_sha1, submitted_script = store_script(request['script'])
                            ws.send({:script_sha1 => script_sha1}.to_json)
                            neo4j_query(<<~END_OF_QUERY, :slug => task[:slug], :sha1 => script_sha1)
                                MERGE (t:Task {slug: {slug}})
                            END_OF_QUERY
                            neo4j_query(<<~END_OF_QUERY, :slug => task[:slug], :sha1 => script_sha1)
                                MERGE (sc:Script {sha1: {sha1}})
                            END_OF_QUERY
                            if task[:slug] == 'pixelflut'
                                neo4j_query(<<~END_OF_QUERY, :sha1 => script_sha1)
                                    MERGE (n:LatestPixelflut)
                                    SET n.sha1 = {sha1}
                                END_OF_QUERY
                            end
                            timestamp = DateTime.now.new_offset(0).to_s
                            result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :slug => task[:slug], :sha1 => script_sha1)
                                MATCH (u:User {email: {email}})
                                MATCH (t:Task {slug: {slug}})
                                MATCH (sc:Script {sha1: {sha1}})
                                MATCH (sb:Submission)
                                WHERE (sb)-[:SUBMITTED_BY]->(u)
                                AND   (sb)-[:FOR]->(t)
                                AND   (sb)-[:USING]->(sc)
                                RETURN ID(sb)
                            END_OF_QUERY
                            submission_node_id = nil
                            if result.empty?
                                submission_node_id = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :slug => task[:slug], :sha1 => script_sha1, :timestamp => timestamp).values.first
                                    MATCH  (u:User {email: {email}})
                                    MATCH  (t:Task {slug: {slug}})
                                    MATCH  (sc:Script {sha1: {sha1}})
                                    CREATE (sb:Submission)
                                    CREATE (sb)-[:SUBMITTED_BY]->(u)
                                    CREATE (sb)-[:FOR]->(t)
                                    CREATE (sb)-[:USING]->(sc)
                                    SET sb.t0 = {timestamp}
                                    SET sb.t1 = {timestamp}
                                    RETURN ID(sb)
                                END_OF_QUERY
                            else
                                submission_node_id = result.first.values.first
                                # update submission timestamp
                                r = neo4j_query(<<~END_OF_QUERY, :submission_node_id => submission_node_id, :timestamp => timestamp)
                                    MATCH (sb:Submission)
                                    WHERE ID(sb) = {submission_node_id}
                                    SET sb.t1 = {timestamp}
                                    RETURN sb;
                                END_OF_QUERY
                            end
                            STDERR.puts "Launching process..."
                            script = ''
                            script += "MYSQL_HOST = 'mysql'\n"
                            script += "MYSQL_USER = '#{@session_user[:mysql_user]}'\n"
                            script += "MYSQL_PASS = '#{@session_user[:mysql_password]}'\n"
                            script += File.read('db.py')
                            script += submitted_script
                            dir = File.join("/raw/sandbox/#{@session_user[:email]}/")
                            FileUtils.rm_rf(dir)
                            FileUtils.mkpath(dir)
                            script_path = File.join(dir, 'main.py')
                            File.open(script_path, 'w') do |f|
                                f.write(script)
                            end
                            script_path = File.join(dir, 'scaffold.py')
                            # TODO: Speed this up, do this once at startup
                            (task[:custom_files] || {}).each_pair do |path, contents|
                                File.open(File.join(dir, path), 'w') do |f|
                                    f.write(contents)
                                end
                            end
                            File.open(script_path, 'w') do |f|
                                scaffold = File.read('scaffold.py')
                                code = StringIO.open do |io|
                                    File.open('os-functions.txt') do |f|
                                        f.each_line do |line|
                                            line.strip!
                                            next if line.empty?
                                            next if ['open', 'path', 'fspath', 'name', 'uname', 'environ', 'getuid', 'getpid'].include?(line)
                                            io.puts "os.#{line} = None"
                                        end
                                        io.puts "os.environ.clear()"
                                    end
                                    io.string
                                end
                                scaffold.sub!('#{DISABLE_OS_FUNCTIONS}', code)
                                scaffold.sub!('#{USE_TASK_CLASS}', task[:input] ? 'True' : 'False')
                                scaffold.sub!('#{INPUT}', task[:input] || '')
                                scaffold.sub!('#{CUSTOM_PRE}', task[:custom_pre] || '')
                                scaffold.sub!('#{CUSTOM_IMPORT_MAIN}', task[:custom_import_main] || '')
                                scaffold.sub!('#{CUSTOM_POST}', task[:custom_post] || '')
                                scaffold.sub!('#{THE_FUNCTION_NAME}', task[:function_name] || '')
                                imports = ''
                                if task[:dungeon]
                                    imports = 'import wizard'
                                end
                                scaffold.sub!('#{IMPORTS}', imports)
                                
                                disable_functions_code = ''
                                disable_functions_patch_code = ''
                                scaffold.scan(/^DISABLE_FUNCTION.*$/).each do |x|
                                    STDERR.puts "Disabling #{x}"
                                    x = x.sub('DISABLE_FUNCTION', '').strip
                                    x = x[1, x.size - 2].strip
                                    x = x.split(',').map do |y|
                                        y.strip!
                                        y[1, y.size - 2]
                                    end
                                    key = x[0]
                                    name = x[1]
                                    disable_functions_code += "def disable_#{name}(*argv):\n"
                                    disable_functions_code += "    sys.stderr.write(\"Die Funktion #{name}() wäre hier normalerweise eine gute Lösung. Allerdings soll diese Aufgabe 'zu Fuß' erledigt werden, weshalb diese Funktion hier nicht erlaubt ist.\")\n"
                                    disable_functions_code += "    exit(2)\n"
                                    disable_functions_patch_code += "@patch('#{key}', disable_#{name})\n"
                                end
                                scaffold.sub!('#{DISABLE_FUNCTIONS}', disable_functions_code + disable_functions_patch_code)
                                f.write(scaffold)
#                                 STDERR.puts scaffold
                                f.puts
                                if task[:dungeon]
                                    File.mkfifo(File.join(dir, 'fifo'))
                                    FileUtils.chmod(0x666, File.join(dir, 'fifo'))
                                    f.puts "dungeon_out = open('/sandbox/#{@session_user[:email]}/fifo', 'w')"
                                    dungeon = dungeon_for_task(task[:slug])
                                    f.puts "fili = Fili(dungeon_out, #{dungeon[:map].to_json}, #{dungeon[:hero].to_json}, #{dungeon[:demons].to_json})"
                                    f.puts task[:dungeon_init] || ''
                                    f.puts "fili.run_it()"
                                    File.open(File.join(dir, 'wizard.py'), 'w') do |f2|
                                        f2.write(File.read('wizard.py'))
                                    end
                                end
                                if task[:pixelflut]
                                    File.mkfifo(File.join(dir, 'fifo'))
                                    FileUtils.chmod(0x666, File.join(dir, 'fifo'))
                                    f.puts "pixelflut_out = open('/sandbox/#{@session_user[:email]}/fifo', 'w')"
                                    f.puts "task = Task(pixelflut_out)"
                                    f.puts "task.run()"
                                    f.puts "task.finalize()"
                                    File.open(File.join(dir, 'pixelflut.py'), 'w') do |f2|
                                        f2.write(File.read('pixelflut.py'))
                                    end
                                end
                                if task[:canvas]
                                    File.mkfifo(File.join(dir, 'fifo'))
                                    FileUtils.chmod(0x666, File.join(dir, 'fifo'))
                                    f.puts "canvas_out = open('/sandbox/#{@session_user[:email]}/fifo', 'w')"
                                    f.puts "task = Task(canvas_out, '#{@session_user[:email]}', 128, 128, #{task[:target_image][:palette]}, #{task[:target_image][:encoded]}, #{task[:target_image][:raw]})"
                                    f.puts "task.run(task.in_data_stream, 128, 128)"
                                    f.puts "task.finalize()"
                                    File.open(File.join(dir, 'canvas.py'), 'w') do |f2|
                                        f2.write(File.read('canvas.py'))
                                    end
                                    File.open(File.join(dir, 'data_stream.py'), 'w') do |f2|
                                        f2.write(File.read('data_stream.py'))
                                    end
                                end
                            end
                            Thread.new do
                                system("docker update --cpus 1.0 --memory 1g #{PYSANDBOX}");
                            end
                                
                            # first kill all processes from this user
                            system("docker exec #{PYSANDBOX} python3 /killuser.py #{@session_user[:email]}")
                            stdin, stdout, stderr, thread = 
                                    Open3.popen3('docker', 'exec', '-i', 
                                                PYSANDBOX, 
                                                "timeout", SCRIPT_TIMEOUT.to_s, 'python3', '-B', '-u', script_path.sub('/raw', ''))
                            @@clients[client_id] = {:stdin => stdin,
                                                    :stdout => stdout,
                                                    :stderr => stderr,
                                                    :thread => thread,
                                                    :process => $?}
                            STDERR.puts "Launched process..."
                            ws.send({:status => 'started'}.to_json)
                            fifo_thread = nil
                            mark_script_passed = false
                            if task[:dungeon] || task[:pixelflut] || task[:canvas]
                                fifo_thread = Thread.new do
                                    fifo = File.open(File.join(dir, 'fifo'), 'r')
                                    fifo_closed = false
                                    result = ''
                                    fifo_buffer = ''
                                    while true do
                                        break if fifo_closed
                                        reads = [fifo]
                                        streams = IO.select(reads)
                                        streams.first.each do |stream|
                                            t = Time.now.to_f
                                            bytes_read = 0
                                            while true do
                                                buffer = nil
                                                begin
                                                    buffer = stream.read_nonblock(4096)
                                                    buffer.force_encoding(Encoding::UTF_8)
                                                    buffer.encode!(Encoding::UTF_16LE, invalid: :replace, replace: "\uFFFD")
                                                    buffer.encode!(Encoding::UTF_8)
                                                rescue EOFError => e
                                                    STDERR.puts e
                                                    fifo_closed = true
                                                    break
                                                rescue StandardError => e
                                                    STDERR.puts e
                                                    break
                                                end
                                                if buffer
                                                    STDERR.puts "FIFO: Received #{buffer.size} bytes: #{buffer}"
                                                    buffer.each_char do |c|
                                                        if c == "\n"
                                                            STDERR.puts ">>> PARSE [#{fifo_buffer}]"
                                                            data = JSON.parse(fifo_buffer)
                                                            if data['status'] == 'passed'
                                                                mark_script_passed = true
                                                            end
                                                            if task[:dungeon]
                                                                ws.send({:dungeon => data}.to_json)
                                                            elsif task[:pixelflut]
                                                                ws.send(data.to_json)
                                                            elsif task[:canvas]
                                                                ws.send(data.to_json)
                                                            end
                                                            fifo_buffer = ''
                                                        else
                                                            fifo_buffer += c
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                    STDERR.puts "Finished fifo thread"
                                end
                            end
                            Thread.new do 
                                result = ''
                                strip_from_stderr = "  File \"/sandbox/#{@session_user[:email]}/scaffold.py\", line 249, in <module>\n    from main import *\n"
                                strip_from_stderr_length = 0
                                streams_closed = false
                                fifo_buffer = ''
                                while true do
                                    break if streams_closed
                                    reads = [@@clients[client_id][:stdout], @@clients[client_id][:stderr]]
                                    reads << fifo if fifo
                                    streams = IO.select(reads)
                                    streams.first.each do |stream|
                                        t = Time.now.to_f
                                        bytes_read = 0
                                        while true do
                                            buffer = nil
                                            begin
                                                if RATE_LIMIT == 0
                                                    buffer = stream.read_nonblock(4096)
                                                else
                                                    while Time.now.to_f < t + bytes_read.to_f / RATE_LIMIT
                                                        sleep 0.1
                                                    end
                                                    buffer = stream.read_nonblock(RATE_LIMIT)
                                                    bytes_read += buffer.size
                                                end
                                                buffer.force_encoding(Encoding::UTF_8)
                                                buffer.encode!(Encoding::UTF_16LE, invalid: :replace, replace: "\uFFFD")
                                                buffer.encode!(Encoding::UTF_8)
                                            rescue EOFError => e
                                                STDERR.puts e
                                                streams_closed = true
                                                break
                                            rescue StandardError => e
                                                STDERR.puts e
                                                break
                                            end
                                            if buffer
                                                STDERR.puts "Received #{buffer.size} bytes: [#{buffer}]"
                                                if stream == @@clients[client_id][:stdout]
                                                    STDERR.puts "(from stdout)"
                                                    ws.send({:stdout => buffer}.to_json)
                                                    result += buffer
                                                elsif stream == @@clients[client_id][:stderr]
                                                    STDERR.puts "(from stderr)"
                                                    accumulator = ''
                                                    buffer.each_char do |c|
                                                        if c == strip_from_stderr[strip_from_stderr_length]
                                                            ws.send({:stderr => accumulator}.to_json) unless accumulator.empty?
                                                            accumulator = ''
                                                            strip_from_stderr_length += 1
                                                            if strip_from_stderr_length == strip_from_stderr.size
                                                                strip_from_stderr_length = 0
                                                            end
                                                        else
                                                            if strip_from_stderr_length > 0
                                                                accumulator += strip_from_stderr[0, strip_from_stderr_length]
                                                                strip_from_stderr_length = 0
                                                            end
                                                            accumulator += c
                                                        end
                                                    end
                                                    ws.send({:stderr => accumulator}.to_json) unless accumulator.empty?
                                                elsif stream == fifo
                                                    STDERR.puts "(from fifo)"
                                                    buffer.each_char do |c|
                                                        if c == "\n"
                                                            ws.send({:dungeon => JSON.parse(fifo_buffer)}.to_json)
                                                            fifo_buffer = ''
                                                        else
                                                            fifo_buffer += c
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                                exit_code = @@clients[client_id][:thread].value.exitstatus
                                STDERR.puts "Script ended with exit code #{exit_code}"
                                fifo_thread.kill unless fifo_thread.nil?
                                if exit_code == 124
                                    timeout_message = "\u001b[46;1m[ Hinweis ]\u001b[0m Das Programm wurde nach #{SCRIPT_TIMEOUT} Sekunden abgebrochen."
                                    ws.send({:stderr => timeout_message}.to_json)
                                end
                                if exit_code == 0
                                    if task[:verify]
                                        # run verification code to see if output is as expected
                                        verify = eval(task[:verify])
                                        if verify.is_a? Proc
                                            if verify.call(result)
                                                mark_script_passed = true
                                            end
                                        elsif verify.is_a? Hash
                                            # test series of inputs with procs
                                            ws.send({:stderr => "\r\n"}.to_json)
                                            all_tests_passed = true
                                            verify.keys.each.with_index do |input, i|
                                                ws.send({:stderr => "\r\u001b[44;1m[ Test ]\u001b[0m "}.to_json)
                                                ws.send({:stderr => "Durchlauf #{i + 1} von #{verify.size}..."}.to_json)
                                                
                                                
                                                test_stdin, test_stdout, test_stderr, test_thread = 
                                                        Open3.popen3('docker', 'exec', '-i', 
                                                                     PYSANDBOX, "timeout", 
                                                                     SCRIPT_TIMEOUT.to_s, 
                                                                     'python3', '-u', 
                                                                     script_path.sub('/raw', ''))
                                                test_stdin.write(input)
                                                test_stdin.close
                                                
                                                unless verify[input].call(test_stdout.read)
                                                    all_tests_passed = false
                                                    ws.send({:stderr => " fehlgeschlagen.\r\n"}.to_json)
                                                    break
                                                end
                                            end
                                            if all_tests_passed
                                                ws.send({:stderr => " ok.\r\n"})
                                                mark_script_passed = true
                                            end
                                        end
                                    else
                                        if !(task[:dungeon] || task[:canvas])
                                            mark_script_passed = true
                                        end
                                    end
                                    if !mark_script_passed
                                        if task[:count_score]
                                            ws.send({:message => "Hinweis: Dein Programm läuft, aber die Aufgabe ist noch nicht erledigt."}.to_json)
                                        end
                                    end
                                end
                                STDERR.puts "mark_script_passed: #{mark_script_passed}"
                                ws.send({:status => 'stopped', :exit_code => exit_code}.to_json)
                                if mark_script_passed
                                    ws.send({:status => 'passed', :slug => task[:slug]}.to_json)
                                    neo4j_query(<<~END_OF_QUERY, :submission_node_id => submission_node_id)
                                        MATCH (sb:Submission)
                                        WHERE ID(sb) = {submission_node_id}
                                        SET sb.correct = true;
                                    END_OF_QUERY
                                end
                                ws.close
                            end
                        end
                    elsif request['action'] == 'kill'
                        # kill all processed from this user
                        timeout_message = "\u001b[46;1m[ Hinweis ]\u001b[0m Das Programm wurde abgebrochen."
                        ws.send({:stderr => timeout_message}.to_json)
                        system("docker exec #{PYSANDBOX} python3 /killuser.py #{@session_user[:email]}")
                    elsif request['action'] == 'stdin'
                        @@clients[client_id][:stdin].write(request['content'])
                    end
                rescue StandardError => e
                    STDERR.puts e
                end
            end

            ws.rack_response
        end
    end
    
    post '/api/upload' do
        require_user!
        entry = params['file']
        filename = entry['filename']
        blob = entry['tempfile'].read
        tag = RandomTag.to_base31(('f' + Digest::SHA1.hexdigest(blob)).to_i(16))[0, 8]
        type = entry['type']
        system("convert \"#{entry['tempfile'].path}\" -resize 512x512^\\> -strip \"#{File::join('/raw/uploads', tag + '.png')}\"")
            update_resolutions(tag)
        respond(:tag => tag)
    end
    
    post '/api/update_user' do
        require_user!
        data = parse_request_data(:required_keys => [:name, :avatar])
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :email => @session_user[:email], :name => data[:name].strip, :avatar=> data[:avatar])
            MATCH (u:User {email: {email}})
            SET u.name = {name}, u.avatar = {avatar}
            RETURN u;
        END_OF_QUERY
    end
    
    def logout()
        sid = request.cookies['sid']
        if sid =~ /^[0-9A-Za-z,]+$/
            current_sid = sid.split(',').first
            if current_sid =~ /^[0-9A-Za-z]+$/
                result = neo4j_query(<<~END_OF_QUERY, :sid => current_sid)
                    MATCH (s:Session {sid: {sid}})
                    DETACH DELETE s;
                END_OF_QUERY
            end
        end
        purge_missing_sessions()
    end

    post '/api/logout' do
        respond(:remaining_sids => logout())
    end
    
    post '/api/login' do
        data = parse_request_data(:required_keys => [:email])
        data[:email] = data[:email].strip.downcase
        unless @@invitations.include?(data[:email])
            respond(:error => 'no_invitation_found')
        end
        assert(@@invitations.include?(data[:email]))
        unless data[:email] == 'fs@hackschule.de'
            assert(@@invitations.include?(data[:email]))
        end
        # create user node if it doesn't already exist
        user = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email])['n'].props
            MERGE (n:User {email: {email}})
            RETURN n;
        END_OF_QUERY
        unless user[:avatar]
            avatar = @@lego_icons[@@invitations[data[:email]][:gender].to_sym].sample
            user = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email], :avatar => avatar)['n'].props
                MATCH (n:User {email: {email}})
                SET n.avatar = {avatar}
                RETURN n;
            END_OF_QUERY
        end
        unless user[:name]
            name = @@invitations[data[:email]][:name]
            user = neo4j_query_expect_one(<<~END_OF_QUERY, :email => data[:email], :name => name)['n'].props
                MATCH (n:User {email: {email}})
                SET n.name = {name}
                RETURN n;
            END_OF_QUERY
        end
        random_code = (0..5).map { |x| rand(10).to_s }.join('')
        if data[:email] == 'fs@hackschule.de' || DEVELOPMENT
            random_code = '123456'
        end
        STDERR.puts ">>> #{data[:email]} #{random_code}"
        tag = RandomTag::generate(8)
        valid_to = Time.now + 3600
        neo4j_query(<<~END_OF_QUERY, :email => data[:email])
            MATCH (l:LoginCode)-[:BELONGS_TO]->(n:User {email: {email}})
            DETACH DELETE l;
        END_OF_QUERY
        neo4j_query(<<~END_OF_QUERY, :email => data[:email], :tag => tag, :code => random_code, :valid_to => valid_to.to_i)
            MATCH (n:User {email: {email}})
            CREATE (l:LoginCode {tag: {tag}, code: {code}, valid_to: {valid_to}})-[:BELONGS_TO]->(n)
            RETURN n;
        END_OF_QUERY
        begin
            deliver_mail do
                to data[:email]
                from SMTP_FROM
                
                subject "Dein Anmeldecode lautet #{random_code}"

                message = StringIO.open do |io|
                    io.puts "<p>Hallo!</p>"
                    io.puts "<p>Dein Anmeldecode lautet: #{random_code}. Der Code ist eine Stunde lang gültig.</p>"
                    io.puts "<p>Falls du diese E-Mail nicht angefordert hast, hat jemand deine E-Mail-Adresse auf <a href='https://hackschule.de/login'>https://hackschule.de/login</a> eingegeben. In diesem Fall musst du nichts weiter tun.</p>"
                    io.puts "<p>Viel Spaß beim programmieren!</p>"
                    io.puts "<p>Michael Specht</p>"
                    io.string
                end
                
                html_part do
                    body message
                end
                
                text_part do
                    body mail_html_to_plain_text(message)
                end
            end
        rescue
            STDERR.puts "Unable to send mail to #{data[:email]}, continuing anyway."
        end
        respond(:tag => tag)
    end
    
    def create_session(email)
        STDERR.puts "ALL SESSIONS: #{all_sessions.to_yaml}"
        sid = RandomTag::generate(24)
        assert(sid =~ /^[0-9A-Za-z]+$/)
        data = {:sid => sid,
                :expires => (DateTime.now() + 365).to_s}
        all_sessions().each do |session|
            other_sid = session[:sid]
            result = neo4j_query(<<~END_OF_QUERY, :email => email, :other_sid => other_sid).map { |x| x['sid'] }
                MATCH (s:Session {sid: {other_sid}})-[:BELONGS_TO]->(u:User {email: {email}})
                DETACH DELETE s;
            END_OF_QUERY
        end
        neo4j_query_expect_one(<<~END_OF_QUERY, :email => email, :data => data)
            MATCH (u:User {email: {email}})
            CREATE (s:Session {data})-[:BELONGS_TO]->(u)
            RETURN s; 
        END_OF_QUERY
        all_sids = all_sessions().map { |x| x[:sid] }
        STDERR.puts all_sessions().to_yaml
        STDERR.puts all_sids.to_yaml
        all_sids.unshift(sid)
        all_sids.join(',')
    end
    
    post '/api/confirm_login' do
        data = parse_request_data(:required_keys => [:tag, :code])
        result = neo4j_query_expect_one(<<~END_OF_QUERY, :tag => data[:tag], :code => data[:code])
            MATCH (l:LoginCode {tag: {tag}, code: {code}})-[:BELONGS_TO]->(u:User)
            RETURN l, u;
        END_OF_QUERY
        user = result['u'].props
        login_code = result['l'].props
        STDERR.puts user.to_yaml
        STDERR.puts login_code.to_yaml
        if Time.at(login_code[:valid_to]) < Time.now
            respond({:error => 'code_expired'})
        end
        assert(Time.at(login_code[:valid_to]) >= Time.now)
        session_id = create_session(user[:email])
        result = neo4j_query(<<~END_OF_QUERY, :tag => data[:tag], :code => data[:code])
            MATCH (l:LoginCode {tag: {tag}, code: {code}})
            DETACH DELETE l;
        END_OF_QUERY
        respond(:session_id => session_id)
    end
    
    def latest_draft_sha1(slug)
        return nil unless user_logged_in?
        require_user!
        own_submissions = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :slug => slug)
            MATCH (sb:Submission)-[:SUBMITTED_BY]->(u:User {email: {email}}),
            (sb)-[:FOR]->(t:Task {slug: {slug}}),
            (sc:Script)<-[:USING]-(sb)
            WHERE NOT COALESCE(sb.correct, false)
            RETURN u.email AS email, sb.t0 AS timestamp, sc.sha1 AS sha1, sb AS submission
            ORDER BY sb.t0 DESC
            LIMIT 1;
        END_OF_QUERY
        own_submissions.empty? ? nil : own_submissions.first['sha1']
    end
    
    def latest_solution_sha1(slug)
        return nil unless user_logged_in?
        require_user!
        own_submissions = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :slug => slug)
            MATCH (sb:Submission {correct: true})-[:SUBMITTED_BY]->(u:User {email: {email}}),
            (sb)-[:FOR]->(t:Task {slug: {slug}}),
            (sc:Script)<-[:USING]-(sb)
            RETURN u.email AS email, sb.t0 AS timestamp, sc.sha1 AS sha1
            ORDER BY sb.t0 DESC
            LIMIT 1;
        END_OF_QUERY
        own_submissions.empty? ? nil : own_submissions.first['sha1']
    end
    
    def read_script_for_sha1(sha1)
        assert(sha1 =~ /^[0-9a-z]+$/)
        File.read("/raw/code/#{sha1}.py")
    end
    
    post '/api/load_script_versions' do
        require_user!
        data = parse_request_data(:required_keys => [:slug])
        versions = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email], :slug => data[:slug])
            MATCH (sb:Submission)-[:SUBMITTED_BY]->(u:User {email: {email}}),
            (sb)-[:FOR]->(t:Task {slug: {slug}}),
            (sc:Script)<-[:USING]-(sb)
            RETURN sb.t0 AS t, sc.sha1 AS sha1, sb.correct AS correct, sc.size AS size, sc.lines AS lines, COALESCE(sb.name, '') AS name
            ORDER BY sb.t0 DESC;
        END_OF_QUERY
        versions.map! do |info|
            entry = {}
            t = DateTime.parse(info['t']).to_time.localtime
            entry[:date] = t.strftime('%d.%m.%Y')
            entry[:time] = t.strftime('%T')
            entry[:sha1] = info['sha1']
            entry[:size] = info['size'] - 1
            entry[:lines] = info['lines']
            entry[:name] = info['name']
            entry[:correct] = info['correct'] || false
            entry
        end
        respond(:versions => versions)
    end
    
    post '/api/load_script_solutions' do
        require_user!
        data = parse_request_data(:required_keys => [:slug])
        solutions = []
        own_solution_count = neo4j_query_expect_one(<<~END_OF_QUERY, :slug => data[:slug], :email => @session_user[:email])['n']
            MATCH (sb:Submission {correct: true})-[:SUBMITTED_BY]->(u:User {email: {email}}),
                    (sb)-[:FOR]->(t:Task {slug: {slug}})
            RETURN COUNT(sb) AS n;
        END_OF_QUERY
        
        if own_solution_count == 0
            respond(:see_other => 'https://youtu.be/dQw4w9WgXcQ')
        else
            versions = neo4j_query(<<~END_OF_QUERY, :slug => data[:slug])
                MATCH (sb:Submission)-[:SUBMITTED_BY]->(u:User),
                    (sb)-[:FOR]->(t:Task {slug: {slug}}),
                    (sc:Script)<-[:USING]-(sb)
                WITH sc.sha1 AS sha1, min(sb.t0) AS t0
                MATCH (sb2:Submission {correct: true, t0: t0})-[:USING]->(sc2:Script {sha1: sha1}),
                    (sb2)-[:SUBMITTED_BY]->(u:User)
                RETURN sb2.t0 AS t, sc2.sha1 AS sha1, sc2.size AS size, sc2.lines AS lines, u.name AS user_name, u.avatar AS user_avatar
                ORDER BY sb2.t0;
            END_OF_QUERY
            seen_sha1 = Set.new()
            versions.each do |info|
                next if seen_sha1.include?(info['sha1'])
                seen_sha1 << info['sha1']
                entry = {}
                t = DateTime.parse(info['t']).to_time.localtime
                entry[:date] = t.strftime('%d.%m.%Y')
                entry[:time] = t.strftime('%T')
                entry[:sha1] = info['sha1']
                entry[:size] = info['size'] - 1
                entry[:lines] = info['lines']
                entry[:user_name] = htmlentities(info['user_name'])
                entry[:user_avatar] = info['user_avatar']
                solutions << entry
            end
            respond(:solutions => solutions.reverse)
        end
    end
    
    post '/api/load_latest_draft' do
        require_user!
        data = parse_request_data(:required_keys => [:slug])
        sha1 = latest_draft_sha1(data[:slug])
        if sha1.nil?
            raise 'nope'
        else
            respond(:script => read_script_for_sha1(sha1))
        end
    end
    
    post '/api/load_latest_solution' do
        require_user!
        data = parse_request_data(:required_keys => [:slug])
        sha1 = latest_solution_sha1(data[:slug])
        if sha1.nil?
            raise 'nope'
        else
            respond(:script => read_script_for_sha1(sha1))
        end
    end
    
    post '/api/load_script' do
        require_user!
        data = parse_request_data(:required_keys => [:sha1])
        respond(:script => read_script_for_sha1(data[:sha1]))
    end
    
    def map_lookup(map, x, y)
        if y >= 0 && y < map.size && x >= 0 && x < map.first.size
            map[y][x]
        else
            '?'
        end
    end
    
    def map_is(map, x, y, which)
        if y >= 0 && y < map.size && x >= 0 && x < map.first.size
            which.include?(map[y][x])
        else
            false
        end
    end
    
    def dungeon_for_task(slug)
        cache_key = "#{slug}"
        @@dungeon_for_task_cache ||= {}
        unless DEVELOPMENT
            if @@dungeon_for_task_cache.include?(cache_key)
                return @@dungeon_for_task_cache[cache_key]
            end
        end
        STDERR.puts "Rendering @@dungeon_for_task_cache[#{cache_key}]"
        tiles = []
        map = @@tasks[slug][:map].split("\n").map { |x| x.strip }.reject { |x| x.empty? }
        height = map.size
        width = map.first.size
        start_pos = nil
        end_pos = nil
        demons_pos = []
        (-1...height+1).each do |y|
            (0...width).each do |x|
                tile = nil
                if x >= 1 && x < width - 1 && y >= 0 && y < height
                    tile = 'floor_1'
                    if map_is(map, x, y, ',')
                        tile = 'floor_2'
                    elsif map_is(map, x, y, '.')
                        tile = 'floor_3'
                    elsif map_is(map, x, y, '/')
                        tile = 'floor_4'
                    elsif map_is(map, x, y, 'e')
                        tile = 'edge'
                    end
                end
                if map_is(map, x, y, 'wbh')
                    if map_is(map, x, y, 'h')
                        tile = 'wall_hole_2'
                    else
                        tile = map_is(map, x, y, 'b') ? 'wall_banner_red' : 'wall_mid'
                    end
                end
                if map_is(map, x, y, 'ULWRxd') || map_is(map, x + 1, y, 'd')
                    tile = nil
                end
                if tile
                    tiles << {:x => x, :y => y, :sprite => tile, :bg => tile.include?('floor')}
                end
                # door
                if map_is(map, x, y, 'd') && !map_is(map, x + 1, y, 'd')
                    tiles << {:x => x - 1, :y => y - 1, :sprite => 'doors_leaf_closed', :scale => 2, :z => 1000}
                    tiles << {:x => x - 2, :y => y - 1, :sprite => 'doors_frame_left', :scale => 1, :z => 1000}
                    tiles << {:x => x + 1, :y => y - 1, :sprite => 'doors_frame_right', :scale => 1, :z => 1000}
                    tiles << {:x => x - 1, :y => y - 1, :sprite => 'doors_frame_top', :scale => 2, :dy => -3, :z => 1000}
                end
                   
                # left top
                if map_is(map, x - 1, y, 'l') && map_is(map, x - 1, y + 1, 'l')
                    tiles << {:x => x - 1, :y => y, :sprite => 'wall_side_mid_left', :z => 1000}
                end
                if map_is(map, x - 1, y, 'l') && !map_is(map, x - 1, y + 1, 'l')
                    tiles << {:x => x - 1, :y => y, :sprite => 'wall_side_front_left', :z => 1000}
                end
                if map_is(map, x - 1, y, 'l') && !map_is(map, x - 1, y - 1, 'l')
                    tiles << {:x => x - 1, :y => y - 1, :sprite => 'wall_side_top_left', :z => 1000}
                end
                # right top
                if map_is(map, x, y, 'r') && map_is(map, x, y + 1, 'r')
                    tiles << {:x => x, :y => y, :sprite => 'wall_side_mid_right', :z => 1000}
                end
                if map_is(map, x, y, 'r') && !map_is(map, x, y + 1, 'r')
                    tiles << {:x => x, :y => y, :sprite => 'wall_side_front_right', :z => 1000}
                end
                if map_is(map, x, y, 'r') && !map_is(map, x, y - 1, 'r')
                    tiles << {:x => x, :y => y - 1, :sprite => 'wall_side_top_right', :z => 1000}
                end
                # upper top
                if map_is(map, x, y, 'wbh') && !map_is(map, x, y - 1, 'wbh')
                    if !map_is(map, x + 1, y, 'd')
                        tiles << {:x => x, :y => y - 1, :sprite => 'wall_top_mid'}
                    end
                end
                # inner wall
                if map_is(map, x, y, 'W')
                    l = map_is(map, x - 1, y, 'W')
                    r = map_is(map, x + 1, y, 'W')
                    if l && r
                        tiles << {:x => x, :y => y, :sprite => 'wall_mid'}
                    else
                        tiles << {:x => x, :y => y, :sprite => r ? 'wall_left' : 'wall_right'}
                    end
                end
                if map_is(map, x, y, 'U')
                    tiles << {:x => x, :y => y - 1, :sprite => 'wall_mid', :z => 6, :dy => 4}
                end
                # inner wall left
                if map_is(map, x, y, 'ULW') && !map_is(map, x - 1, y, 'ULW') 
                    if !map_is(map, x - 1, y, 'x')
                        tiles << {:x => x, :y => y - 1, :sprite => 'wall_side_mid_right', :z => 6}
                        if !map_is(map, x, y - 1, 'ULW')
                            tiles << {:x => x, :y => y - 2, :sprite => 'wall_side_top_right', :z => 1000, :dy => 4}
                        end
                    else
                        tiles << {:x => x - 1, :y => y - 1, :sprite => 'wall_side_front_left', :dy => 4, :z => 5}
                        tiles << {:x => x, :y => y - 2, :sprite => 'wall_corner_bottom_left', :dx => -5, :dy => 4, :z => 4}
                    end
                end
                # inner wall right
                if map_is(map, x, y, 'URW') && !map_is(map, x + 1, y, 'URW')
                    if !map_is(map, x + 1, y, 'x')
                        tiles << {:x => x, :y => y - 1, :sprite => 'wall_side_mid_left', :z => 6}
                        if !map_is(map, x, y - 1, 'URW')
                            tiles << {:x => x, :y => y - 2, :sprite => 'wall_side_top_left', :z => 100, :dy => 4}
                        end
                    else
                        tiles << {:x => x + 1, :y => y - 1, :sprite => 'wall_side_front_right', :dy => 4, :z => 4}
                        tiles << {:x => x, :y => y - 2, :sprite => 'wall_corner_bottom_right', :dx => 5, :dy => 4, :z => 4}
                    end
                end
                if map_is(map, x, y, 'U')
                    l = map_is(map, x - 1, y, 'U')
                    r = map_is(map, x + 1, y, 'U')
                    if l && r
                        tiles << {:x => x, :y => y - 2, :sprite => 'wall_top_mid', :z => 100, :dy => 4}
                    else
                        tiles << {:x => x, :y => y - 2, :sprite => l ? 'wall_top_right' : 'wall_top_left', :z => 100, :dy => 4}
                    end
                end
                if map_is(map, x, y, 'W')
                    l = map_is(map, x - 1, y, 'W')
                    r = map_is(map, x + 1, y, 'W')
#                     if l && r
                        tiles << {:x => x, :y => y - 1, :sprite => 'wall_top_mid'}
#                     else
                        tiles << {:x => x, :y => y - 1, :sprite => l ? 'wall_top_right' : 'wall_top_left', :z => 101}
#                     end
                end

                # fountain
                if map_is(map, x, y - 1, 'f')
                    tiles << {:x => x, :y => y - 2, :sprite => 'wall_fountain_top'}
                    tiles << {:x => x, :y => y - 1, :sprite => 'wall_fountain_mid_blue_anim_f0', :fountain_top => true}
                    tiles << {:x => x, :y => y, :sprite => 'wall_fountain_basin_blue_anim_f0', :fountain_bottom => true}
                end
                
                # column
                if map_lookup(map, x, y - 1) == 'C'
                    tiles << {:x => x, :y => y, :sprite => 'column_top', :dy => -8 - 32}
                    tiles << {:x => x, :y => y, :sprite => 'column_mid', :dy => -8 - 16}
                    tiles << {:x => x, :y => y, :sprite => 'column_base', :dy => -8}
                end
                
                if map_is(map, x, y, 'D')
                    tiles << {:x => x, :y => y, :sprite => 'big_demon_idle_anim_f0', :scale => 2, :z => 48, :flip_x => true, :dx => -8, :dy => -13, :demon => true, :shift_y => -9}
                    demons_pos << [x, y]
                end
                if map_is(map, x, y, 'z')
                    tiles << {:x => x, :y => y, :sprite => 'chest_empty_open_anim_f2', :dy => -2}
                    end_pos = [x, y]
                end
                if map_is(map, x, y, 'c')
                    tiles << {:x => x, :y => y, :sprite => 'coin_anim_f0', :coin => true, :dy => -1}
                end
                if map_is(map, x, y, 'a')
                    tiles << {:hero => true, :x => x, :y => y, :dir => 0, :sprite => 'wiz_right_0', :dy => -14}
                    start_pos = [x, y]
                end
                if y == height - 1 && x > 0 && x < width - 1
                    tiles << {:x => x, :y => y + 1, :sprite => 'edge'}
                end
            end
        end
        tiles.map! { |x| x[:y] += 1; x }
            
        @@dungeon_for_task_cache[cache_key] = {:map => map, :tiles => tiles, :width => width, :height => height + 2, 
                  :hero => {:x => start_pos[0], :y => start_pos[1], :dir => 0},
                  :demons => demons_pos.map { |m| {:x => m[0], :y => m[1], :dir => 0}}}
    end
    
    post '/api/load_dungeon' do
        data = parse_request_data(:required_keys => [:slug])
        result = dungeon_for_task(data[:slug])
        respond(:width => result[:width], :height => result[:height], 
                :tiles => result[:tiles], :hero => result[:hero])
    end
    
    def compile_files(key, mimetype, paths)
        @@compiled_files[key] ||= {:timestamp => nil, :content => nil}
        
        latest_file_timestamp = paths.map do |path|
            File.mtime(File.join('/static', path))
        end.max
        
        if @@compiled_files[key][:timestamp].nil? || @@compiled_files[key][:timestamp] < latest_file_timestamp
            @@compiled_files[key][:content] = StringIO.open do |io|
                paths.each do |path|
                    io.puts File.read(File.join('/static', path))
                end
                io.string
            end
            @@compiled_files[key][:sha1] = Digest::SHA1.hexdigest(@@compiled_files[key][:content])
            @@compiled_files[key][:timestamp] = latest_file_timestamp
        end
        response.headers['Last-Modified'] = latest_file_timestamp.httpdate
        response.headers['ETag'] = @@compiled_files[key][:sha1]
        respond_raw_with_mimetype(@@compiled_files[key][:content], mimetype)
    end
    
    get '/api/compiled.js' do
        files = [
            '/bower_components/jquery-3.4.1.min.js',
            '/popper.min.js',
            '/bower_components/bootstrap/dist/js/bootstrap.min.js',
            '/bower_components/fontawesome/js/all.min.js',
            '/bower_components/jquery.cookie/jquery.cookie.js',
            '/ace/src-min-noconflict/ext-language_tools.js',
            '/xterm/xterm.js',
            '/xterm/xterm-addon-fit.js',
            '/xterm/xterm-addon-attach.js',
            '/code.js'
        ]
        
        key = :js
        compile_files(key, 'application/javascript', files)
    end
    
    get '/api/compiled.css' do
        files = [
            '/bower_components/bootstrap/dist/css/bootstrap.min.css',
            '/bower_components/fontawesome/css/all.min.css',
            '/styles.css',
            '/xterm/xterm.css'
        ]
        
        key = :css
        compile_files(key, 'text/css', files)
    end

    post '/api/store_script' do
        require_user!
        data = parse_request_data(:required_keys => [:script, :slug],
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        sha1, script = store_script(data[:script])
        # fetch name if available
        result = neo4j_query(<<~END_OF_QUERY, :sha1 => sha1, :slug => data[:slug], :email => @session_user[:email])
            MATCH (sc:Script {sha1: {sha1}})<-[:USING]-(sb:Submission)-[:FOR]->(t:Task {slug: {slug}})
            MATCH (u:User {email: {email}})
            WHERE (sb)-[:SUBMITTED_BY]->(u)
            RETURN COALESCE(sb.name, '') AS name;
        END_OF_QUERY
        if result.size > 0
            name = result.first['name']
        end
        respond(:sha1 => sha1, :name => name)
    end
    
    post '/api/save_script_as' do
        require_user!
        data = parse_request_data(:required_keys => [:slug, :sha1, :name],
                                  :max_body_length => 1024 * 1024,
                                  :max_string_length => 1024 * 1024)
        neo4j_query(<<~END_OF_QUERY, :sha1 => data[:sha1], :slug => data[:slug], :email => @session_user[:email], :name => data[:name])
            MATCH (sc:Script {sha1: {sha1}})<-[:USING]-(sb:Submission)-[:FOR]->(t:Task {slug: {slug}})
            MATCH (u:User {email: {email}})
            WHERE (sb)-[:SUBMITTED_BY]->(u)
            SET sb.name = {name};
        END_OF_QUERY
        respond(:ok => 'yeah')
    end
    
    def nav_items()
        StringIO.open do |io|
            nav_items = []
            if @original_path == 'task'
                nav_items << :scripts
            end
            nav_items << ['/', 'Aufgaben', 'fa fa-map']
#                          ['/hintergrund', 'Hintergrund'],
#                          ['/hilfe', 'Hilfe', 'fa fa-question'],
#                          ['/impressum', 'Impressum'],
#                          ['/kontakt', 'Kontakt']
            if user_logged_in?
#                 nav_items << ['/trophy_road', 'Trophäenpfad', 'fa fa-medal']
                nav_items << :profile
            else
                nav_items << ['/login', 'Anmelden', 'fa fa-sign-in-alt']
            end
            nav_items.each do |x|
                if x == :profile
                    io.puts "<li class='nav-item dropdown'>"
                    io.puts "<a class='nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdown' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                    io.puts "<div class='icon'><img class='menu-avatar' src='/gen/#{@session_user[:avatar]}-48.png' /></div><span class='menu-user-name'>#{htmlentities(@session_user[:name])}</span>"
                    io.puts "</a>"
                    io.puts "<div class='dropdown-menu dropdown-menu-right' aria-labelledby='navbarDropdown'>"
                    io.puts "<a class='dropdown-item nav-icon' href='/profil'><div class='icon'><i class='fa fa-user'></i></div><span class='label'>Profil</span></a>"
                    sessions = all_sessions()
                    if sessions.size > 1
                        io.puts "<div class='dropdown-divider'></div>"
                        sessions[1, sessions.size - 1].each do |entry|
                            local_sids = ([entry[:sid]] + sessions.reject { |x| x[:sid] == entry[:sid]}.map { |x| x[:sid] }).join(',')
                            io.puts "<a class='dropdown-item nav-icon' href='#' onclick=\"set_sid_cookie('#{local_sids}');\"><img class='icon menu-avatar' src='/gen/#{entry[:user][:avatar]}-48.png' /><span class='label'>#{htmlentities(entry[:user][:name])}</span></a>"
                        end
                    end
                    io.puts "<a class='dropdown-item nav-icon' href='/login'><div class='icon'><i class='fa fa-sign-in-alt'></i></div><span class='label'>Zusätzliche Anmeldung...</span></a>"
                    if teacher_logged_in?
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='/admin'><div class='icon'><i class='fa fa-wrench'></i></div><span class='label'>Administration</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/users'><div class='icon'><i class='fa fa-users'></i></div><span class='label'>Nutzer</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/live_signin'><div class='icon'><i class='fa fa-clipboard-list'></i></div><span class='label'>Live-Anmeldungen</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/scratch'><div class='icon'><i class='fa fa-pen'></i></div><span class='label'>Scratchpad</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='/camera'><div class='icon'><i class='fa fa-camera'></i></div><span class='label'>Dokumentenkamera</span></a>"
                    end
                    io.puts "<div class='dropdown-divider'></div>"
                    io.puts "<a class='dropdown-item nav-icon' href='#' onclick='perform_logout();'><div class='icon'><i class='fa fa-sign-out-alt'></i></div><span class='label'>Abmelden</span></a>"
                    io.puts "</div>"
                    io.puts "</li>"
                elsif x == :scripts
                    if user_logged_in?
                        latest_draft = latest_draft_sha1(@task_slug)
                        latest_solution = latest_solution_sha1(@task_slug)
                        io.puts "<li class='nav-item dropdown'>"
                        io.puts "<a class='nav-icon nav-link nav-icon dropdown-toggle' href='#' id='navbarDropdownScripts' role='button' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false'>"
                        io.puts "<div class='icon'><i class='fa fa-edit'></i></div>Programm"
                        io.puts "</a>"
                        io.puts "<div class='dropdown-menu' aria-labelledby='navbarDropdownScripts'>"
                        io.puts "<a class='mi-load-version dropdown-item nav-icon #{(latest_draft.nil? && latest_solution.nil?) ? 'disabled' : ''}' href='#' onclick='load_version();'><div class='icon'><i class='fa fa-folder-open'></i></div><span class='label'>Version laden…</span></a>"
                        io.puts "<a class='dropdown-item nav-icon' href='#' onclick='name_script_modal();'><div class='icon'><i class='fa fa-save'></i></div><span class='label'>Speichern unter…</span></a>"
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='dropdown-item nav-icon' href='#' onclick='share_script_modal();'><div class='icon'><i class='fa fa-share-alt'></i></div><span class='label'>Programm teilen</span></a>"
                        io.puts "<div class='dropdown-divider'></div>"
                        io.puts "<a class='mi-reset-script-to-template dropdown-item nav-icon' href='#' onclick='reset_script_to_template();'><div class='icon'><i class='fa fa-trash-alt'></i></div><span class='label'>Vorlage neu laden</span></a>"
                        io.puts "</div>"
                        io.puts "</li>"
                    end
                else
                    io.puts "<li class='nav-item text-nowrap'>"
                    io.puts "<a class='nav-link nav-icon' href='#{x[0]}' #{x[3]}><div class='icon'><i class='#{x[2]}'></i></div>#{x[1]}</a>"
                    io.puts "</li>"
                end
            end
            io.string
        end
    end
    
    def print_live_signin_codes()()
        StringIO.open do |io|
            result = neo4j_query(<<~END_OF_QUERY, {:timestamp => Time.now.to_i})
                MATCH (l:LoginCode)-[:BELONGS_TO]->(u:User)
                WHERE l.valid_to > {timestamp}
                RETURN l.code, u.email, u.name
                ORDER BY l.valid_to;
            END_OF_QUERY
            result.each do |entry|
                io.puts "<div class='col-md-6' style='font-size: 300%;'>"
                io.puts "#{entry['u.name']}: #{entry['l.code']}"
                io.puts "</div>"
            end
            STDERR.puts result.to_yaml
            io.string
        end
    end
    
    def list_all_tasks(show_cat_slug = nil)
        StringIO.open do |io|
            solved_tasks = Set.new()
            unless user_logged_in?
                io.puts "<div class='alert alert-warning' role='alert'>"
                io.puts "Du bist momentan nicht angemeldet. Bitte <a href='/login'>melde dich an</a>, um Aufgaben lösen zu können."
                io.puts "</div>"
            else
                # find all passed tasks
                result = neo4j_query(<<~END_OF_QUERY, :email => @session_user[:email])
                    MATCH (u:User {email: {email}})<-[:SUBMITTED_BY]-(sb:Submission {correct: true})-[:FOR]->(t:Task) 
                    RETURN t.slug;            
                END_OF_QUERY
                solved_tasks = Set.new(result.map { |x| x.values.first })
            end
            last_cat = nil
            printed_tasks_per_cat = 0
            max_printed_tasks_per_cat = 4
            max_printed_tasks_per_cat = nil if show_cat_slug
            max_printed_tasks_per_cat = nil
            
            @@task_keys_sorted.each do |k|
                task = @@tasks[k]
                unless teacher_logged_in?
                    next unless task[:enabled]
                end
                unless show_cat_slug.nil?
                    next unless task[:cat_slug] == show_cat_slug
                end
                if last_cat != task[:cat]
                    printed_tasks_per_cat = 0
                    unless last_cat.nil?
                        io.puts "</div></div></div>" 
                        io.puts "<hr />"
                    end
                    io.puts "<div class='row'><div class='col-md-12' style='margin-top: 15px;'>"
                    unless show_cat_slug
                        io.puts "<a class='float-right btn btn-success' href='/cat/#{task[:cat_slug]}'>#{task[:cat]}&nbsp;&nbsp;<i class='fa fa-chevron-right'></i></a>"
                        io.puts "<h4 style='margin-bottom: 20px;'>#{task[:cat]}</h4>" 
                        io.puts "#{@@cat_config[task[:cat_slug]][:teaser]}"
                    end
                    # progress meter
                    task_count = @@cat_info[task[:cat]].select { |x| @@tasks[x][:count_score] }.size
                    solved_task_count = (Set.new(@@cat_info[task[:cat]]) & solved_tasks).size
                    io.puts "<div class='row'>"
                    io.puts "<div class='col-md-12'>"
                    io.puts "<div style='margin-bottom: 10px;' class='progress'>"
                    io.puts "<div class='progress-bar progress-bar-striped bg-success' role='progressbar' style='width: #{solved_task_count * 100 / task_count}%' aria-valuenow='#{solved_task_count}' aria-valuemin='0' aria-valuemax='#{task_count}'>#{solved_task_count} von #{task_count} Aufgaben gelöst</div>"
                    io.puts "</div>"
                    io.puts "</div>"
                    io.puts "</div>"
                    
                    io.puts "<div class='row'>"
                    last_cat = task[:cat]
                end
                if max_printed_tasks_per_cat.nil? || printed_tasks_per_cat < max_printed_tasks_per_cat
                    io.puts "<div class='col-lg-3 col-md-4 col-sm-6 #{show_cat_slug ? '' : "hs-card-index-#{printed_tasks_per_cat}"}'}'>"
                    io.puts "<div class='card' style='#{task[:enabled] ? '' : 'opacity: 0.5;'}'>"
                    io.puts "<div class='card-header #{task[:enabled] ? '' : 'text-muted'}'>#{task[:title]}"
                    if task[:count_score]
                        if task[:difficulty] == 'easy'
                            io.puts "<span title='leicht' class='badge task-badge easy'><i class='fa fa-lightbulb'></i></span>"
                        elsif task[:difficulty] == 'medium'
                            io.puts "<span title='mittel' class='badge task-badge medium'><i class='fa fa-lightbulb'></i></span>"
                        elsif task[:difficulty] == 'hard'
                            io.puts "<span title='nicht ganz trivial' class='badge task-badge hard'><i class='fa fa-lightbulb'></i></span>"
                        end
                    else
                            io.puts "<span title='leicht' class='badge task-badge sandbox'><i class='fa fa-vial'></i></span>"
                    end
                    
                    io.puts "</div>"
                    io.puts "<div class='card-body #{task[:enabled] ? '' : 'text-muted'}'>"
                    io.puts "<div class='card-text'>#{task[:description]}</div>"
                    io.puts "</div>"
                    draft_sha1 = latest_draft_sha1(k)
                    solution_sha1 = latest_solution_sha1(k)
                    io.puts "<div class='card-footer text-muted'>"
#                     io.puts "<div class='btn-group'>"
                    label = 'Aufgabe lösen'
                    label = 'Sandbox starten' unless task[:count_score]
                    io.puts "  <a type='button' href='/task/#{task[:slug]}' class='btn btn-sm btn-primary'><i class='fa fa-pen'></i>&nbsp;&nbsp;#{label}</a>"
#                     io.puts "  <button type='button' class='#{draft_sha1.nil? && solution_sha1.nil? ? 'disabled' : ''} btn btn-sm btn-primary dropdown-toggle dropdown-toggle-split' data-toggle='dropdown' aria-haspopup='true' aria-expanded='false' />"
#                     io.puts "  <div class='dropdown-menu'>"
#                     io.puts "    <a class='fix-this-link dropdown-item #{draft_sha1.nil? ? 'disabled' : ''}' data-href='/task/#{task[:slug]}/#{draft_sha1}' href='/task/#{task[:slug]}/#{draft_sha1}'>Letzten Entwurf laden</a>"
#                     io.puts "    <a class='fix-this-link dropdown-item #{solution_sha1.nil? ? 'disabled' : ''}' href='/task/#{task[:slug]}/#{solution_sha1}'>Lösung laden</a>"
#                     io.puts "  </div>"
#                     io.puts "</div>"
                    if solved_tasks.include?(task[:slug])
                        io.puts "<span class='text-success task-badge-solved'><i class='fa fa-medal'></i></span>"
                    end
                    io.puts "</div>"
                    io.puts "</div>"
                    io.puts "</div>"
                    printed_tasks_per_cat += 1
                end
            end
            io.puts "</div></div>"
            io.puts "</div>"
            io.puts "<div class='row'>"
            io.puts "<div class='col-md-8 offset-md-2'>"
            io.puts "<div class='pixelflut-poster'>"
            io.puts "<img class='pixelflut-poster' src='#{WEB_ROOT}/pixelflut/?#{Time.now.to_i}' />"
            link = "/task/pixelflut"
            temp = neo4j_query(<<~END_OF_QUERY)
                MATCH (n:LatestPixelflut)
                RETURN n.sha1;
            END_OF_QUERY
            if temp.size > 0
                link += "/#{temp.first['n.sha1']}"
            end
            io.puts "<a type='button' href='#{link}' class='btn btn-sm btn-primary'><i class='fa fa-pen'></i> &nbsp;&nbsp;Zur Pixelflut</a>"
            io.puts "</div>"
            io.puts "</div>"
            io.puts "</div>"
            io.string
        end
    end
    
    def print_cat(cat_slug)
        StringIO.open do |io|
            io.puts "<h2 style='margin-bottom: 20px;'>#{@@cat_config[cat_slug][:title]}</h2>"
            io.puts @@cat_config[cat_slug][:teaser]
            io.puts @@cat_config[cat_slug][:description]
            io.puts list_all_tasks(cat_slug)
            io.string
        end
    end
    
    def bytes_to_str(ai_Size)
        if ai_Size < 1024
            return "#{ai_Size} B"
        elsif ai_Size < 1024 * 1024
            return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0)} kB"
        elsif ai_Size < 1024 * 1024 * 1024
            return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0 / 1024.0)} MB"
        elsif ai_Size < 1024 * 1024 * 1024 * 1024
            return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0 / 1024.0 / 1024.0)} GB"
        end
        return "#{sprintf('%1.1f', ai_Size.to_f / 1024.0 / 1024.0 / 1024.0 / 1024.0)} TB"
    end
    
    def current_user_solved_this_task(slug)
        return false unless user_logged_in?
        solution = neo4j_query(<<~END_OF_QUERY, {:email => @session_user[:email], :slug => slug})
            MATCH (sb:Submission {correct: true})-[:SUBMITTED_BY]->(u:User {email: {email}}),
                  (sb)-[:FOR]->(t:Task {slug: {slug}}),
                  (sb)-[:USING]->(sc:Script)
            RETURN sb 
            LIMIT 1;
        END_OF_QUERY
        !solution.empty?
    end
    
    def show_daily_activity(days)
        require_teacher!
        date = (DateTime.now.new_offset(0) - days).to_s
        date = "#{date[0, 10]}T00:00:00+00:00"
        date_date = DateTime.parse(date)
        StringIO.open do |io|
            results = neo4j_query(<<~END_OF_QUERY, {:date => date}).map { |x| {:submission => x['sb'].props, :user => x['u'].props} }
                MATCH (sb:Submission)-[:SUBMITTED_BY]->(u:User)
                WHERE sb.t0 >= {date} OR sb.t1 >= {date}
                RETURN sb, u
                ORDER BY sb.t0, sb.t1;
            END_OF_QUERY
            users = {}
            results.each do |entry|
                submission = entry[:submission]
                email = entry[:user][:email]
                next unless is_teacher_for_user?(email)
                users[email] ||= {}
                users[email][:name] ||= entry[:user][:name]
                users[email][:avatar] ||= entry[:user][:avatar]
                users[email][:s] ||= []
                [:t0, :t1].each do |k|
                    t = submission[k]
                    next unless t >= date
                    f = (DateTime.parse(t) - date_date).to_f
                    d = f.floor
                    t = ((f - d) * 10000).to_i / 100.0
                    users[email][:s] << [d, t]
                end
            end
            io.puts "<h4>Aktivität</h4>"
            io.puts "<table class='daily-activity table table-sm'>"
            last_group = nil
            users.keys.sort do |a, b|
                (@@invitations[a][:group] == @@invitations[b][:group]) ?
                (users[b][:s].size <=> users[a][:s].size) :
                (@@invitations[a][:group] <=> @@invitations[b][:group])
                
            end.each do |email|
                group = @@invitations[email][:group]
                if last_group != group
                    last_group = group
                    io.puts "<tr><th style='background-color: #ddd;' colspan='2'>#{group}</th></tr>"
                end
                io.puts "<tr>"
                io.puts "<td class='daily-activity-user'><img class='menu-avatar' src='/gen/#{users[email][:avatar]}-48.png' /> #{htmlentities(users[email][:name])}</td>"
                io.puts "<td class='daily-activity-d'>"
                io.puts "<div>"
                (0..days).each do |i|
                    io.puts "<span class='line d#{i}' style='top: #{i * 3 + 1}px;'></span>"
                end
                users[email][:s].each do |pair|
                    d = pair[0]
                    t = pair[1]
                    io.puts "<span class='d d#{d}' style='left: #{t}%;'></span>"
                end
                io.puts "</div>"
                io.puts "</td>"
                io.puts "</tr>"
                io.puts "</div>"
            end
            io.puts "</table>"
            io.string
        end
    end
    
    def is_teacher_for_user?(email)
        require_teacher!
        @@teachers[@session_user[:email]].include?((@@invitations[email] || {})[:group])
    end
    
    def show_teacher_dashboard()
        require_teacher!
        StringIO.open do |io|
            users = neo4j_query(<<~END_OF_QUERY).map { |x| x['u'].props }
                MATCH (u:User)
                RETURN u
                ORDER BY u.name;
            END_OF_QUERY
            user_for_email = {}
            users.each do |user|
                next unless is_teacher_for_user?(user[:email])
                user_for_email[user[:email]] = user
            end
            submissions = neo4j_query(<<~END_OF_QUERY).map { |x| {:user => x['u'].props, :submission => x['sb'].props, :script => x['sc'].props, :task => x['t'].props}}
                MATCH (sb:Submission)-[:SUBMITTED_BY]->(u:User),
                        (sb)-[:FOR]->(t:Task),
                        (sb)-[:USING]->(sc:Script)
                RETURN sb, sc, t, u
                ORDER BY sb.t0 DESC;
            END_OF_QUERY
            submissions_for_user = {}
            submissions.each do |entry|
                next unless is_teacher_for_user?(entry[:user][:email])
                submissions_for_user[entry[:user][:email]] ||= {}
                submissions_for_user[entry[:user][:email]][entry[:task][:slug]] ||= {}
                if entry[:submission][:correct]
                    submissions_for_user[entry[:user][:email]][entry[:task][:slug]][:latest_solution] ||= entry[:script][:sha1] 
                else
                    submissions_for_user[entry[:user][:email]][entry[:task][:slug]][:latest_draft] ||= entry[:script][:sha1] 
                end
            end
            io.puts "<h4>Aufgaben</h4>"
            io.puts "<table class='table table-striped table-sm narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th rowspan='2'>Name</th>"
            @@cats_sorted.each do |cat|
                io.puts "<th colspan='#{@@cat_info[cat].size}'>#{cat}</th>"
            end
            io.puts "</tr>"
            io.puts "<tr>"
            @@task_keys_sorted.each.with_index do |k, i|
                io.puts "<th>##{i + 1}</th>"
            end
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            last_group = nil
            @@user_groups.keys.sort.each do |group|
                @@user_groups[group].select do |email|
                    user_for_email.include?(email) && is_teacher_for_user?(email)
                end.sort do |a, b|
                    (user_for_email[a][:name] || '') <=> (user_for_email[b][:name] || '')
                end.each do |email|
                    user = user_for_email[email]
                    next unless user[:name]
                    if last_group != @@invitations[email][:group]
                        last_group = @@invitations[email][:group]
                        io.puts "<tr><th style='background-color: #ddd;' colspan='#{@@tasks.size + 1}'>#{group}</th></tr>"
                    end
                    io.puts "<tr>"
                    io.puts "<td>"
                    io.puts "<img class='menu-avatar' src='/gen/#{user[:avatar]}-48.png' style='width: 20px; height: 20px; position: relative; top: -2px;' />&nbsp;"
                    io.puts "#{user[:name]}"
                    io.puts "</td>"
                    @@task_keys_sorted.each.with_index do |k, i|
                        io.puts "<td>"
                        submissions = (submissions_for_user[user[:email]] || {})[k]
                        if submissions.nil?
                            io.puts "--"
                        else
                            if submissions[:latest_solution]
                                io.puts "<a href='/task/#{k}/#{submissions[:latest_solution]}'><i class='fa fa-medal text-success'></i></a>"
                            elsif submissions[:latest_draft]
                                io.puts "<a href='/task/#{k}/#{submissions[:latest_draft]}'><i class='fa text-warning fa-pen'></i></a>"
                            end
                        end
                        io.puts "</td>"
                    end
                    io.puts "</tr>"
                end
            end
            io.puts "</tbody>"
            io.puts "</table>"
#             io.puts show_daily_activity(7)
            io.puts "<h4>Ausgeführte Programme</h4>"
            io.puts "<table class='table table-striped table-sm narrow'>"
            io.puts "<thead>"
            io.puts "<tr>"
            io.puts "<th>Zeit</th>"
            io.puts "<th>Name</th>"
            io.puts "<th>Aufgabe</th>"
            io.puts "<th>Skript</th>"
            io.puts "<th class='text-right'>Größe</th>"
            io.puts "<th class='text-right'>Zeilen</th>"
            io.puts "<th>Kopien</th>"
            io.puts "</tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            submissions = neo4j_query(<<~END_OF_QUERY).map { |x| {:user => x['u'].props, :submission => x['sb'].props, :script => x['sc'].props, :task => x['t'].props}}
                MATCH (sb:Submission)-[:SUBMITTED_BY]->(u:User),
                      (sb)-[:FOR]->(t:Task),
                      (sb)-[:USING]->(sc:Script)
                RETURN sb, sc, t, u
                ORDER BY sb.t0 DESC
                LIMIT 1000;
            END_OF_QUERY
            
            script_task_order = []
            script_task_dict = {}
            submissions.reverse.each do |entry|
                next unless is_teacher_for_user?(entry[:user][:email])
                script = entry[:script]
                task = entry[:task]
                script_task = "#{script[:sha1]}/#{task[:slug]}"
                unless script_task_dict.include?(script_task)
                    script_task_order << script_task
                    script_task_dict[script_task] = {
                        :sha1 => script[:sha1],
                        :size => script[:size],
                        :lines => script[:lines],
                        :slug => task[:slug],
                        :user => entry[:user],
                        :t => entry[:submission][:t0],
                        :others => Set.new(),
                        :others_order => []
                    }
                end
                if entry[:user][:email] != script_task_dict[script_task][:user][:email]
                    unless script_task_dict[script_task][:others].include?(entry[:user][:email])
                        script_task_dict[script_task][:others_order] << entry[:user]
                    end
                end
            end
            script_task_order.reverse.each do |key|
                info = script_task_dict[key]
                io.puts "<tr>"
                io.puts "<td>#{DateTime.parse(info[:t]).to_time.localtime.strftime('%d.%m.%Y %T')}</td>"
                user = info[:user]
                io.puts "<td>"
                io.puts "<img class='menu-avatar' src='/gen/#{user[:avatar]}-48.png' style='width: 20px; height: 20px; position: relative; top: -2px;' />&nbsp;"
                io.puts "#{user[:name]}"
                io.puts "</td>"
                io.puts "<td>#{@@tasks[info[:slug]][:title]}</td>"
                io.puts "<td><a href='/task/#{info[:slug]}/#{info[:sha1]}'><code>#{info[:sha1]}</code></a></td>"
                io.puts "<td class='text-right'>#{bytes_to_str(info[:size])}</td>"
                io.puts "<td class='text-right'>#{info[:lines] - 1}</td>"
                io.puts "<td>"
                info[:others_order].each do |other|
                    io.puts "<img class='menu-avatar' title='#{other[:name]}' src='/gen/#{other[:avatar]}-48.png' style='width: 20px; height: 20px; position: relative; top: -2px;' />&nbsp;"
                end
                io.puts "</td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            timestamps = neo4j_query(<<~END_OF_QUERY).map { |x| {:t => x['t'], :email => x['email'] } }
                MATCH (s:Submission)-[:SUBMITTED_BY]-(u:User)
                RETURN s.t0 AS t, u.email AS email
                ORDER BY t;
            END_OF_QUERY
            histogram = {}
            submissions_for_user = {}
            spare_time_submissions_for_user = {}
            timestamps.each do |row|
                email = row[:email]
                t = row[:t]
                submissions_for_user[email] ||= 0
                submissions_for_user[email] += 1
                next if @@teachers.include?(row[:email])
                d = DateTime.parse(t).to_time.localtime
                key = "#{d.wday}/#{d.strftime('%H')}"
                histogram[key] ||= 0
                histogram[key] += 1
                if ([0, 6].include?(d.wday)) || (d.hour < 8 || d.hour > 16)
                    spare_time_submissions_for_user[email] ||= 0
                    spare_time_submissions_for_user[email] += 1
                end
            end
            max_count = histogram.values.max || 1
            # #4aa03f => green
            io.puts "<table class='table'>"
            wdays = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']
            io.puts "<th></th>"
            (0..23).each do |h|
                k = sprintf('%02d', h)
                io.puts "<th style='text-align: center;'>#{k}</th>"
            end
            (1..7).each do |_wday|
                wday = _wday % 7
                io.puts "<tr>"
                io.puts "<th style='text-align: center;'>#{wdays[wday]}</th>"
                (0..23).each do |h|
                    k = sprintf('%d/%02d', wday, h)
                    v = histogram[k] || 0
                    f = (v.to_f / max_count) ** 0.5
                    r = 0xff - (0xff - 0x4a) * f
                    g = 0xff - (0xff - 0xa0) * f
                    b = 0xff - (0xff - 0x3f) * f
                    io.puts sprintf("<td style='text-align: center; background-color: #%02x%02x%02x;'>#{v}</td>", r, g, b)
                end
                io.puts "</tr>"
            end
            io.puts "</table>"
            io.puts "Außerhalb von 8 bis 17 Uhr: #{spare_time_submissions_for_user.keys.size} / #{submissions_for_user.keys.size}" 
            io.puts "<table class='table'>"
            io.puts "<tr><th>E-Mail</th><th>Name</th><th>Submissions</th></tr>"
            submissions_for_user.keys.sort do |a, b|
                submissions_for_user[b] <=> submissions_for_user[a]
            end.each do |email|
                user = user_for_email[email] || {}
                io.puts "<tr><td>#{email}</td><td>"
                io.puts "<img class='menu-avatar' src='/gen/#{user[:avatar]}-48.png' style='width: 20px; height: 20px; position: relative; top: -2px;' />&nbsp;"
                io.puts "#{user[:name]}</td><td>#{submissions_for_user[email]}</td></tr>"
            end
            io.puts "</table>"
#             STDERR.puts timestamps.to_yaml
            io.string
        end
    end
    
    def show_user_list()
        require_teacher!
        StringIO.open do |io|
            users = neo4j_query(<<~END_OF_QUERY).map { |x| x['u'].props }
                MATCH (u:User)
                RETURN u
                ORDER BY u.name;
            END_OF_QUERY
            user_for_email = {}
            users.each do |user|
                next unless is_teacher_for_user?(user[:email])
                user_for_email[user[:email]] = user
            end
            io.puts "<table class='table table-striped table-sm narrow table-responsive' style='font-size: 80%;'>"
            io.puts '<tbody>'
            io.puts '<thead>'
            io.puts '<tr>'
            io.puts '<th>Name</th>'
            io.puts '<th>E-Mail</th>'
            io.puts '</tr>'
            io.puts '</thead>'
            last_group = nil
            @@user_groups.keys.sort.each do |group|
                @@user_groups[group].select do |email|
                    user_for_email.include?(email) && is_teacher_for_user?(email)
                end.sort do |a, b|
                    (user_for_email[a][:name] || '') <=> (user_for_email[b][:name] || '')
                end.each do |email|
                    user = user_for_email[email]
                    group = @@invitations[email][:group]
                    next unless user[:name]
                    if last_group != group
                        last_group = group
                        io.puts "<tr class='click-row' data-group='#{group}'><th style='background-color: #ddd;' colspan='2'>#{group}</th></tr>"
                    end
                    io.puts "<tr class='click-row' data-email='#{email}'>"
                    io.puts "<td style='max-width: 150px; overflow: hidden; text-overflow: ellipsis;'>"
                    io.puts "<img class='menu-avatar' src='/gen/#{user[:avatar]}-48.png' style='width: 20px; height: 20px; position: relative; top: -2px;' />&nbsp;"
                    io.puts "#{user[:name]}"
                    io.puts "</td>"
                    io.puts "<td style='max-width: 150px; overflow: hidden; text-overflow: ellipsis;'>#{email}</td>"
                    io.puts "</tr>"
                end
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.string
        end
    end
    
    post '/api/get_user_info' do
        require_user!
        data = parse_request_data(:required_keys => [:email])
        email = data[:email]
        submissions = neo4j_query(<<~END_OF_QUERY, {:email => email}).map { |x| {:sb => x['sb'].props, :sc => x['sc'].props, :t => x['t'].props } }
            MATCH (u:User {email: {email}})<-[:SUBMITTED_BY]-(sb:Submission)-[:USING]->(sc:Script)
            MATCH (sb)-[:FOR]->(t:Task)
            RETURN sb, sc, t ORDER BY sb.t0 DESC;
        END_OF_QUERY
        html = StringIO.open do |io|
            io.puts "<h3>#{@@invitations[email][:name]}</h3>"
            
            io.puts "<table class='table table-sm narrow table-striped' style='position: absolute; right: 15px; width: 400px;'>"
            io.puts "<thead>"
            io.puts "<tr><th>Aufgabe</th><th>Status</th><th>Subs</th></tr>"
            io.puts "</thead>"
            io.puts "<tbody>"
            tasks = {}
            submissions.each do |entry|
                slug = entry[:t][:slug]
                tasks[slug] ||= {
                    :solved => false,
                    :tries => 0
                }
                tasks[slug][:tries] += 1
                if entry[:sb][:correct]
                    tasks[slug][:solved] = true
                end
            end
            @@task_keys_sorted.each do |k|
                task = @@tasks[k]
                io.puts "<tr>"
                io.puts "<td>#{task[:title]}</td>"
                io.puts "<td>#{(tasks[k] || {})[:solved]}</td>"
                io.puts "<td>#{(tasks[k] || {})[:tries]}</td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "<div style='position: absolute; left: 15px; right: 15px; padding-right: 420px;'>"
            io.puts "<table class='table table-sm narrow table-striped'>"
            io.puts "<thead>"
            io.puts "<th>Datum</th>"
            io.puts "<th>Zeit</th>"
            io.puts "<th>Aufgabe</th>"
            io.puts "<th>Skript</th>"
            io.puts "<th>Zeilen</th>"
            io.puts "<th>Größe</th>"
            io.puts "</thead>"
            io.puts "<tbody>"
            submissions.each do |entry|
                io.puts "<tr class='open-script-row' data-href='/task/#{entry[:t][:slug]}/#{entry[:sc][:sha1]}'>"
                d = DateTime.parse(entry[:sb][:t0])
                io.puts "<td>#{WEEK_DAYS[d.wday]}, #{d.strftime('%d.%m.%Y')}</td>"
                io.puts "<td>#{d.strftime('%H:%M:%S')}</td>"
                io.puts "<td>#{(@@tasks[entry[:t][:slug]] || {})[:title] || entry[:t][:slug]}</td>"
                link = entry[:sb][:correct] ? "<i class='fa fa-medal text-success'></i>" : "<i class='fa fa-pen text-warning'></i>"
                io.puts "<td>#{link}</td>"
                io.puts "<td>#{entry[:sc][:lines]}</td>"
                io.puts "<td>#{bytes_to_str(entry[:sc][:size])}</td>"
                io.puts "</tr>"
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
        respond(:html => html)
    end
    
    post '/api/get_group_info' do
        require_user!
        data = parse_request_data(:required_keys => [:group])
        group = data[:group]
        users = neo4j_query(<<~END_OF_QUERY).map { |x| x['u'].props }
            MATCH (u:User)
            RETURN u
            ORDER BY u.name;
        END_OF_QUERY
        user_for_email = {}
        users.each do |user|
            next unless is_teacher_for_user?(user[:email])
            user_for_email[user[:email]] = user
        end
        emails = []
        @@user_groups[group].select do |email|
            user_for_email.include?(email) && is_teacher_for_user?(email)
        end.each do | email|
            emails << email
        end
        submissions = neo4j_query(<<~END_OF_QUERY, {:emails => emails})
            MATCH (u:User)<-[:SUBMITTED_BY]-(sb:Submission)-[:USING]->(sc:Script)
            WHERE u.email IN {emails}
            MATCH (sb)-[:FOR]->(t:Task)
            RETURN u.email AS email, sb.t0 AS t0, sb.correct AS correct, sc.sha1 AS sha1, t.slug AS slug ORDER BY sb.t0 DESC;
        END_OF_QUERY
        stats = {}
        stats_max = 0
        submissions.each do |entry|
            email = entry['email']
            t0 = entry['t0']
            correct = entry['correct'] || false
            sha1 = entry['sha1']
            slug = entry['slug']
            stats[email] ||= {}
            yw = Date.parse(t0).strftime('%Y-%V')
            stats[email][yw] ||= {}
            stats[email][yw][sha1] = true
            stats_max = stats[email][yw].size if stats[email][yw].size > stats_max
        end
        p = Date.parse('2020-08-10')
        while p.wday != 1
            p -= 1
        end
        yw0 = p #- 20 * 7
        yw_list = []
        p = yw0
        monday_for_yw = {}
        while p <= Date.today do
            yw = p.strftime('%Y-%V')
            yw_list << yw 
            monday_for_yw[yw] = p.strftime('%d.%m.')
            p += 7
        end
        html = StringIO.open do |io|
            io.puts "<h3>#{group}</h3>"
            
            io.puts "<table class='table table-sm narrow' style='font-size: 80%;'>"
            io.puts "<thead>"
            io.puts "<th>Name</th>"
            yw_list.each do |yw|
                ds = monday_for_yw[yw] || 'X'
                io.puts "<th style='text-align: center;'>#{ds}</th>"
            end
            io.puts "</thead>"
            io.puts "<tbody>"
            @@user_groups[group].select do |email|
                user_for_email.include?(email) && is_teacher_for_user?(email)
            end.sort do |a, b|
                (user_for_email[a][:name] || '') <=> (user_for_email[b][:name] || '')
            end.each do |email|
                user = user_for_email[email]
                group = @@invitations[email][:group]
                next unless user[:name]
                io.puts "<tr class='click-row' data-email='#{email}'>"
                io.puts "<td style='max-width: 100px; overflow: hidden; text-overflow: ellipsis;'>"
                io.puts "<img class='menu-avatar' src='/gen/#{user[:avatar]}-48.png' style='width: 20px; height: 20px; position: relative; top: -2px;' />&nbsp;"
                io.puts "#{user[:name]}"
                io.puts "</td>"
                yw_list.each do |yw|
                    count = (((stats[email] || {})[yw]) || {}).size
                    f = 0
                    if stats_max > 0
                        f = (count.to_f / stats_max) ** 0.5
                    end
                    r = 0xff - (0xff - 0x4a) * f
                    g = 0xff - (0xff - 0xa0) * f
                    b = 0xff - (0xff - 0x3f) * f
                    if count > 0
                        io.puts sprintf("<td style='text-align: center; background-color: #%02x%02x%02x;'>", r, g, b)
                        io.puts count
                        io.puts "</td>"
                    else
                        io.puts "<td style='text-align: center;'>&ndash;</td>"
                    end
                end
            end
            io.puts "</tbody>"
            io.puts "</table>"
            io.puts "</div>"
            io.string
        end
        respond(:html => html)
    end
    
    def list_all_lego_icons
        StringIO.open do |io|
            @@lego_icons[:all].sort.each do |k|
                io.puts "<img data-avatar='#{k}' class='profile-icon-preview' src='/gen/#{k}-128.png'>"
            end
            io.string
        end
    end
    
    get '/*' do
        path = request.env['REQUEST_PATH']
        assert(path[0] == '/')
        path = path[1, path.size - 1]
        path = 'index' if path.empty?
        path = path.split('/').first
        brand = 'Hackschule'
        if path.include?('..') || (path[0] == '/')
            status 404
            return
        end
        
        slug = nil
        task = nil
        sha1 = nil
        cat_slug = nil
        if path == 'task'
            parts = request.env['REQUEST_PATH'].split('/')
            slug = parts[2]
            sha1 = parts[3]
            if @@tasks.include?(slug)
                task = @@tasks[slug]
                if sha1 =~ /[^0-9a-z]/
                    redirect "#{WEB_ROOT}/task/#{slug}/#{sha1.gsub(/[^0-9a-z]/, '')}", 302
                end
            else
                status 404
                return
            end
        elsif path == 'cat'
            parts = request.env['REQUEST_PATH'].split('/')
            cat_slug = parts[2]
            unless @@cat_config.include?(cat_slug)
                status 404
                return
            end
        end
        
        @page_title = ''
        @page_description = ''

        unless path.include?('/')
            unless path.include?('.') || path[0] == '_'
                original_path = path.dup
                show_offer = {}
                
                path = File::join('/static', path) + '.html'
                if File::exists?(path)
                    content = File::read(path, :encoding => 'utf-8')
                    
                    @original_path = original_path
                    @task_slug = slug
                    if original_path == 'cat'
                        content.gsub!('#{cat_slug}', cat_slug)
                    elsif original_path == 'task'
                        task_has_screen = task[:screen] == true
                        task_has_dungeon = task[:dungeon] == true
                        task_has_pixelflut = task[:pixelflut] == true
                        task_has_canvas = task[:canvas] == true
                        content.gsub!('#{TASK_TITLE}', task[:title])
                        content.gsub!('#{TASK_SLUG}', task[:slug])
                        content.gsub!('#{TASK_CONFIG}', task.to_json)
                        if sha1
                            content.gsub!('#{TASK_TEMPLATE}', read_script_for_sha1(sha1).strip + "\n")
                        else
                            content.gsub!('#{TASK_TEMPLATE}', task[:template].strip + "\n")
                        end
                        description = task[:description]
                        if task[:target_image]
                            description += StringIO.open do |io|
                                io.puts "<p>Die Palette für dieses Bild hat #{task[:target_image][:palette].size} Farben:</p>"
                                task[:target_image][:palette].each.with_index do |color, i|
                                    io.puts "<div class='palette_swatch' style='background-color: #{color};'><span>#{i}</span></div>"
                                end
                                if task[:target_image][:encoded].size == task[:target_image][:raw].size
                                    io.puts "<p style='margin-top: 0.5em;'>In dieser Aufgabe wurde das Bild nicht komprimiert, jedes Byte entspricht also genau einem Pixel.</p>"
                                else
                                    io.puts "<p style='margin-top: 0.5em;'>In dieser Aufgabe wurde das Bild auf <strong>#{task[:target_image][:encoded].size * 100 / task[:target_image][:raw].size}%</strong> der ursprünglichen Größe komprimiert.</p>"
                                end
                                io.string
                            end
                        end
                        cat_slug = task[:cat_slug]
                        cat = @@cat_config[cat_slug]
                        if cat[:config]['dungeon'] || cat[:config]['canvas']
                            description += "\n<hr />\n" + cat[:description]
                        end
                        unless task[:hints].empty?
                            description += "<hr />"
                            description += "<div class='hint'>"
                            description += "<p><em>Falls du Probleme hast, diese Aufgabe zu lösen, kannst du dir einen Hinweis geben lassen:</em></p>"
                            task[:hints].each.with_index do |hint, hint_index|
                                description += "<span class='hint-button btn btn-sm btn-outline-secondary'>#{task[:hints].size > 1 ? "#{hint_index + 1}. " : ''}Hinweis anzeigen</span>" 
                                description += "<div style='display: none;'><hr />#{hint}"
                            end
                            task[:hints].each.with_index do |hint, hint_index|
                                description += "</div>"
                            end
                            description += "</div>"
                        end
                        content.sub!('#{TASK_DESCRIPTION}', description)
                    elsif original_path == 'c'
                        parts = request.env['REQUEST_PATH'].split('/')
                        login_tag = parts[2]
                        login_code = parts[3]
                    end
                    
                    template_path = '_template'
                    template_path = "/static/#{template_path}.html"
                    @template ||= {}
                    @template[template_path] ||= File::read(template_path, :encoding => 'utf-8')
                    
                    s = @template[template_path].dup
                    s.sub!('#{CONTENT}', content)
                    s.gsub!('{BRAND}', brand);
                    purge_deleted_sids_code = ''
                    existing_sids = purge_missing_sessions()
                    sent_sids = request.cookies['sid']
                    if existing_sids != sent_sids
                        purge_deleted_sids_code = StringIO.open do |io|
                            io.puts "var options = {};"
                            io.puts "options.expires = 365;"
                            io.puts "options.path = '/';"
                            io.puts "$.cookie('sid', '#{existing_sids}', options);"
                            io.string
                        end
                    end
                    s.sub!('#{PURGE_DELETED_SIDS}', purge_deleted_sids_code)
                    page_css = ''
                    if File::exist?(path.sub('.html', '.css'))
                        page_css = "<style>\n#{File::read(path.sub('.html', '.css'))}\n</style>"
                    end
                    s.sub!('#{PAGE_CSS_HERE}', page_css)
                    compiled_js_sha1 = (((@@compiled_files || {})[:js] || {})[:sha1] || RandomTag.generate(12))[0, 12]
                    compiled_css_sha1 = (((@@compiled_files || {})[:css] || {})[:sha1] || RandomTag.generate(12))[0, 12]
                    meta_tags = ''

                    while true
                        index = s.index('#{')
                        break if index.nil?
                        length = 2
                        balance = 1
                        while index + length < s.size && balance > 0
                            c = s[index + length]
                            balance -= 1 if c == '}'
                            balance += 1 if c == '{'
                            length += 1
                        end
                        code = s[index + 2, length - 3]
                        begin
                            s[index, length] = eval(code).to_s || ''
                        rescue
                            STDERR.puts "Error while evaluating:"
                            STDERR.puts code
                            raise
                        end
                    end
                    s.gsub!('<!--PAGE_TITLE-->', @page_title)
                    s.gsub!('<!--PAGE_DESCRIPTION-->', @page_description)
                    s
                else
                    status 404
                end
            else
                status 404
            end
        else
            status 404
        end
    end

    run! if app_file == $0
end

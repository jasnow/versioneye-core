class CommonCrawlWorker < Worker


  def work
    connection = get_connection
    connection.start
    channel = connection.create_channel
    queue   = channel.queue("common_crawl", :durable => true)

    log_msg = " [*] Waiting for messages in #{queue.name}. To exit press CTRL+C"
    puts log_msg
    log.info log_msg

    begin
      queue.subscribe(:ack => true, :block => true) do |delivery_info, properties, message|
        puts " [x] Received #{message}"

        process_work message

        channel.ack(delivery_info.delivery_tag)
      end
    rescue => e
      log.error e.message
      log.error e.backtrace.join("\n")
      connection.close
    end
  end


  def process_work message
    return nil if message.to_s.empty?

    if message.eql?("cocoa_pods_1")
      CocoapodsCrawler.crawl
      GithubVersionCrawler.crawl
    end

    log.info "Job done for #{message}"
  rescue => e
    log.error e.message
    log.error e.backtrace.join("\n")
  end


end

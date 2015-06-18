require "bundler"
Bundler.require

require "./lib/initializer"
require "clockwork"

$stdout.sync = true

module Clockwork

  every(1.minute, "top-off-workers") do
    Pliny.log(task: 'top-off-workers') do
      Transferatu::WorkerManager.new.check_workers
    end
  end

  every(1.minute, "log-metrics") do
    pending_xfer_count = Transferatu::Transfer.pending.count
    active_xfer_count = Transferatu::Transfer.in_progress.count
    Pliny.log(:"sample#pending_xfer_count" => pending_xfer_count,
              :"sample#active_xfer_count" => active_xfer_count)
  end

  every(5.minutes, "run-scheduled-transfers") do
    # This schedules 250 backups each time it is run, but no harm comes from
    # from running it more frequently, and we have over 2000 scheduled backups
    # for some hours, so 5 minutes means at minimum 3000 jobs will be processed
    #
    # N.B.: If this becomes too heavyweight, we may want to pull it
    # out into its own Procfile entry instead of using Clockwork
    scheduled_time = Time.now
    resolver = Transferatu::ScheduleResolver.new
    processor = Transferatu::ScheduleProcessor.new(resolver)
    manager =  Transferatu::ScheduleManager.new(processor)
    Pliny.log(task: 'run-scheduled-transfers', scheduled_for: scheduled_time) do
      manager.run_schedules(scheduled_time)
    end
  end

  every(4.hours, "mark-restart") do
    Transferatu::AppStatus.mark_update
  end
end

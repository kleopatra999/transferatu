require "spec_helper"

module Transferatu
  describe Transfer do
    let(:t) { create(:transfer) }

    describe ".begin_next_pending" do
      let(:time)  { Time.now }
      let!(:t0)   { create(:transfer, created_at: time - 10) }
      let!(:t1)   { create(:transfer) }
      let!(:t2)   { create(:transfer, started_at: time - 1) }
      let!(:t3)   { create(:transfer, started_at: time - 30, finished_at: time - 5) }

      it "finds the oldest transfer" do
        expect(Transfer.begin_next_pending.uuid).to eq(t0.uuid)
      end
      it "begins the transfer it returns" do
        xfer = Transfer.begin_next_pending
        expect(xfer.started_at).to_not be_nil
      end
      it "returns nil when there are no pending transfers" do
        t0.update(started_at: Time.now)
        t1.update(started_at: Time.now)
        expect(Transfer.begin_next_pending).to be_nil
      end
      it "prioritizes non-scheduled transfers" do
        create(:transfer,
               created_at: t0.created_at - 10.minutes,
               schedule: create(:schedule))
        expect(Transfer.begin_next_pending.uuid).to eq(t0.uuid)
      end
    end

    describe ".in_progress" do
      before do
        @pending = create(:transfer)
        @running = create(:transfer, started_at: Time.now)
        @canceled = create(:transfer, started_at: Time.now, canceled_at: Time.now + 1)
        @failed = create(:transfer, started_at: Time.now,
                         finished_at: Time.now + 1, succeeded: false)
        @completed = create(:transfer, started_at: Time.now,
                            finished_at: Time.now + 1, succeeded: true)
      end

      it "should only include running transfers" do
        in_progress = Transfer.in_progress.all
        expect(in_progress).to include(@running)
        expect(in_progress).to_not include(@pending)
        expect(in_progress).to_not include(@canceled)
        expect(in_progress).to_not include(@failed)
        expect(in_progress).to_not include(@completed)
      end
    end

    describe ".pending" do
      before do
        @pending = create(:transfer)
        @running = create(:transfer, started_at: Time.now)
        @canceled = create(:transfer, started_at: Time.now, canceled_at: Time.now + 1)
        @failed = create(:transfer, started_at: Time.now,
                         finished_at: Time.now + 1, succeeded: false)
        @completed = create(:transfer, started_at: Time.now,
                            finished_at: Time.now + 1, succeeded: true)
      end

      it "should only include running transfers" do
        pending = Transfer.pending.all
        expect(pending).to include(@pending)
        expect(pending).to_not include(@running)
        expect(pending).to_not include(@canceled)
        expect(pending).to_not include(@failed)
        expect(pending).to_not include(@completed)
      end
    end

    describe "#cancel" do
      it "flags a transfer as canceled, finished, and failed" do
        expect(t.canceled_at).to be_nil
        before_cancel = Time.now
        t.cancel
        expect(t.canceled_at).to be > before_cancel
        expect(t.finished_at).to be > before_cancel
        expect(t.succeeded).to be false
      end

      it "does not update the canceled time for an already-canceled transfer" do
        expect(t.canceled_at).to be_nil
        before_cancel = Time.now
        t.cancel
        after_first_cancel = Time.now
        t.cancel
        expect(t.canceled_at).to be > before_cancel
        expect(t.canceled_at).to be < after_first_cancel
      end

      it "does not do anything for an already-finished transfer" do
        t.complete
        before_cancel = Time.now
        t.cancel
        expect(t.canceled?).to be false
        expect(t.succeeded?).to be true
        expect(t.finished_at).to be < before_cancel
      end
    end

    describe "#canceled?" do
      it "is false when a transfer is not canceled" do
        expect(t.canceled?).to be false
      end
      it "is true when the transfer is canceled" do
        t.update(canceled_at: Time.now)
        expect(t.canceled?).to be true
      end
    end

    describe "#started?" do
      it "is false when a transfer has not started" do
        expect(t.started?).to be false
      end
      it "is true when a transfer has started" do
        t.update(started_at: Time.now)
        expect(t.started?).to be true
      end
    end

    describe "#finished?" do
      it "is false when a transfer has not finished" do
        expect(t.finished?).to be false
      end
      it "is true when a transfer has finished successfully" do
        t.update(finished_at: Time.now, succeeded: true)
        expect(t.finished?).to be true
      end
      it "is true when a transfer has finished unsuccessfully" do
        t.update(finished_at: Time.now, succeeded: false)
        expect(t.finished?).to be true
      end
    end

    describe "#succeeded?" do
      it "is false if a transfer has not succeeded" do
        expect(t.succeeded?).to be false
      end
      it "is true if a transfer has succeeded" do
        t.update(finished_at: Time.now, succeeded: true)
        expect(t.succeeded?).to be true
      end
    end

    describe "#complete" do
      it "flags a transfer as successfully completed" do
        t.complete
        expect(t.finished_at).to_not be_nil
        expect(t.succeeded).to be true
      end

      it "does not update the finished_at if previously completed" do
        t.complete
        first_completion_before = Time.now
        expect(t.finished_at).to be < first_completion_before
        expect(t.succeeded).to be true
        t.complete
        expect(t.finished_at).to be < first_completion_before
        expect(t.succeeded).to be true
      end

      it "raises if trying to complete an already-failed transfer" do
        t.fail
        expect { t.complete }.to raise_error(Transferatu::Transfer::AlreadyFailed)
      end
    end

    describe "#failed?" do
      it "is false if a transfer has not failed" do
        expect(t.failed?).to be false
      end

      it "is true if a transfer has failed" do
        t.update(finished_at: Time.now, succeeded: false)
        expect(t.failed?).to be true
      end
    end

    describe "#fail" do
      it "flags a transfer as unsuccessfully completed" do
        t.fail
        expect(t.finished_at).to_not be_nil
        expect(t.succeeded).to be false
      end

      it "does not update the finished_at if previously failed" do
        t.fail
        first_failure_before = Time.now
        expect(t.finished_at).to be < first_failure_before
        expect(t.succeeded).to be false
        t.fail
        expect(t.finished_at).to be < first_failure_before
        expect(t.succeeded).to be false
      end

      it "raises if trying to fail an already-completed transfer" do
        t.complete
        expect { t.fail }.to raise_error(Transferatu::Transfer::AlreadySucceeded)
      end
    end

    describe "#retry" do
      it "flags a completed transfer as not started" do
        t.complete
        t.retry
        expect(t.succeeded?).to be false
        expect(t.finished?).to be false
        expect(t.in_progress?).to be false
      end

      it "flags a canceled transfer as not started" do
        t.cancel
        t.retry
        expect(t.succeeded?).to be false
        expect(t.finished?).to be false
        expect(t.in_progress?).to be false
      end

      it "flags an in-progress transfer as not started" do
        t.update(started_at: Time.now)
        t.retry
        expect(t.succeeded?).to be false
        expect(t.finished?).to be false
        expect(t.in_progress?).to be false
      end

      it "flags a failed transfer as not started" do
        t.fail
        t.retry
        expect(t.succeeded?).to be false
        expect(t.finished?).to be false
        expect(t.in_progress?).to be false
      end
    end

    describe "#in_progress?" do
      it "is false when a transfer has not started" do
        expect(t.in_progress?).to be false
      end
      it "is true when a transfer has started and not finished" do
        t.update(started_at: Time.now)
        expect(t.in_progress?).to be true
      end
      it "is false when a transfer has started and finished" do
        t.update(started_at: Time.now, finished_at: Time.now)
        expect(t.in_progress?).to be false
      end
    end

    describe "#destroy" do
      it "flags the transfers as deleted" do
        t.destroy
        expect(t.deleted?).to be true
      end

      it "cancels the transfer if it is in progress" do
        t.update(started_at: Time.now)
        t.destroy
        expect(t.canceled_at).to_not be_nil
      end
    end

    describe "#log" do
      it "stores non-transient log messages" do
        allow(t.group).to receive(:log)
        t.log "hello", transient: false
        expect(t.logs).to satisfy { |logs| logs.find { |entry| entry.message == 'hello' } }
      end
      it "does not store transient log messages" do
        allow(t.group).to receive(:log)
        t.log "hello", transient: true
        expect(t.logs).to be_empty
      end
      %i(info warning error).each do |level|
        it "logs #{level} messages to its group" do
          expect(t.group).to receive(:log)
          t.log "hello", level: level
        end
      end
      it "does not log internal messages to its group" do
        expect(t.group).to_not receive(:puts)
        t.log "hello", level: :internal
      end
    end

    describe "#mark_progress" do
      it "updates the processed_bytes accordingly" do
        t.mark_progress(12345678)
        expect(t.processed_bytes).to eq 12345678
      end
      it "logs a transient message with the updated size" do
        expect(t).to receive(:log) do |line, args|
          expect(args[:transient]).to be true
          expect(line).to match(/progress: 12345678/)
        end
        t.mark_progress(12345678)
      end
      it "updates updated_at even when no other progress has been made" do
        t.mark_progress(12345678)
        before_update = Time.now
        t.mark_progress(12345678)
        expect(t.updated_at).to be > before_update
      end
    end
  end
end

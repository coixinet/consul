require 'rails_helper'

describe Legislation::Process do
  let(:process) { create(:legislation_process) }

  it "is valid" do
    expect(process).to be_valid
  end

  describe "dates validations" do
    it "is invalid if debate_start_date is present but debate_end_date is not" do
      process = build(:legislation_process, debate_start_date: Date.current, debate_end_date: "")
      expect(process).to be_invalid
      expect(process.errors.messages[:debate_end_date]).to include("can't be blank")
    end

    it "is invalid if debate_end_date is present but debate_start_date is not" do
      process = build(:legislation_process, debate_start_date: nil, debate_end_date: Date.current)
      expect(process).to be_invalid
      expect(process.errors.messages[:debate_start_date]).to include("can't be blank")
    end

    it "is invalid if allegations_start_date is present but debate_end_date is not" do
      process = build(:legislation_process, allegations_start_date: Date.current, allegations_end_date: "")
      expect(process).to be_invalid
      expect(process.errors.messages[:allegations_end_date]).to include("can't be blank")
    end

    it "is invalid if debate_end_date is present but allegations_start_date is not" do
      process = build(:legislation_process, allegations_start_date: nil, allegations_end_date: Date.current)
      expect(process).to be_invalid
      expect(process.errors.messages[:allegations_start_date]).to include("can't be blank")
    end
  end

  describe "date ranges validations" do
    it "is invalid if end_date is before start_date" do
      process = build(:legislation_process, start_date: Date.current, end_date: Date.current - 1.day)
      expect(process).to be_invalid
      expect(process.errors.messages[:end_date]).to include("must be on or after the start date")
    end

    it "is valid if end_date is the same as start_date" do
      process = build(:legislation_process, start_date: Date.current - 1.day, end_date: Date.current - 1.day)
      expect(process).to be_valid
    end

    it "is invalid if debate_end_date is before debate start_date" do
      process = build(:legislation_process, debate_start_date: Date.current, debate_end_date: Date.current - 1.day)
      expect(process).to be_invalid
      expect(process.errors.messages[:debate_end_date]).to include("must be on or after the debate start date")
    end

    it "is valid if debate_end_date is the same as debate_start_date" do
      process = build(:legislation_process, debate_start_date: Date.current - 1.day, debate_end_date: Date.current - 1.day)
      expect(process).to be_valid
    end

    it "is invalid if allegations_end_date is before allegations_start_date" do
      process = build(:legislation_process, allegations_start_date: Date.current, allegations_end_date: Date.current - 1.day)
      expect(process).to be_invalid
      expect(process.errors.messages[:allegations_end_date]).to include("must be on or after the allegations start date")
    end

    it "is valid if allegations_end_date is the same as allegations_start_date" do
      process = build(:legislation_process, allegations_start_date: Date.current - 1.day, allegations_end_date: Date.current - 1.day)
      expect(process).to be_valid
    end
  end

  describe "filter scopes" do
    before do
      @process_1 = create(:legislation_process, start_date: Date.current - 2.days, end_date: Date.current + 1.day)
      @process_2 = create(:legislation_process, start_date: Date.current + 1.day, end_date: Date.current + 3.days)
      @process_3 = create(:legislation_process, start_date: Date.current - 4.days, end_date: Date.current - 3.days)
    end

    it "filters open" do
      open_processes = ::Legislation::Process.open

      expect(open_processes).to include(@process_1)
      expect(open_processes).not_to include(@process_2)
      expect(open_processes).not_to include(@process_3)
    end

    it "filters next" do
      next_processes = ::Legislation::Process.next

      expect(next_processes).to include(@process_2)
      expect(next_processes).not_to include(@process_1)
      expect(next_processes).not_to include(@process_3)
    end

    it "filters past" do
      past_processes = ::Legislation::Process.past

      expect(past_processes).to include(@process_3)
      expect(past_processes).not_to include(@process_2)
      expect(past_processes).not_to include(@process_1)
    end
  end

  describe "#status" do
    it "detects planned phase" do
      process.update_attributes(start_date: Date.current + 2.days)
      expect(process.status).to eq(:planned)
    end

    it "detects closed phase" do
      process.update_attributes(end_date: Date.current - 2.days)
      expect(process.status).to eq(:closed)
    end

    it "detects open phase" do
      expect(process.status).to eq(:open)
    end
  end

end

# == Schema Information
#
# Table name: legislation_processes
#
#  id                         :integer          not null, primary key
#  title                      :string
#  description                :text
#  additional_info            :text
#  start_date                 :date
#  end_date                   :date
#  debate_start_date          :date
#  debate_end_date            :date
#  draft_publication_date     :date
#  allegations_start_date     :date
#  allegations_end_date       :date
#  result_publication_date    :date
#  hidden_at                  :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  summary                    :text
#  debate_phase_enabled       :boolean          default(FALSE)
#  allegations_phase_enabled  :boolean          default(FALSE)
#  draft_publication_enabled  :boolean          default(FALSE)
#  result_publication_enabled :boolean          default(FALSE)
#  published                  :boolean          default(TRUE)
#  proposals_phase_start_date :date
#  proposals_phase_end_date   :date
#  proposals_phase_enabled    :boolean
#  proposals_description      :text
#

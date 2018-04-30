class Legislation::Answer < ActiveRecord::Base
  acts_as_paranoid column: :hidden_at
  include ActsAsParanoidAliases

  belongs_to :question, class_name: 'Legislation::Question', foreign_key: 'legislation_question_id',
                        inverse_of: :answers, counter_cache: true
  belongs_to :question_option, class_name: 'Legislation::QuestionOption', foreign_key: 'legislation_question_option_id',
                               inverse_of: :answers, counter_cache: true
  belongs_to :user, dependent: :destroy, inverse_of: :legislation_answers

  validates :question, presence: true, uniqueness: { scope: :user_id}
  validates :question_option, presence: true
  validates :user, presence: true
end

# == Schema Information
#
# Table name: legislation_answers
#
#  id                             :integer          not null, primary key
#  legislation_question_id        :integer
#  legislation_question_option_id :integer
#  user_id                        :integer
#  hidden_at                      :datetime
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#

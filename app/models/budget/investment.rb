require 'csv'

class Budget
  class Investment < ActiveRecord::Base
    SORTING_OPTIONS = %w(id title supports).freeze

    include Rails.application.routes.url_helpers
    include Measurable
    include Sanitizable
    include Taggable
    include Searchable
    include Reclassification
    include Followable
    include Communitable
    include Imageable
    include Mappable
    include Documentable
    documentable max_documents_allowed: 3,
                 max_file_size: 3.megabytes,
                 accepted_content_types: [ "application/pdf" ]

    acts_as_votable
    acts_as_paranoid column: :hidden_at
    include ActsAsParanoidAliases
    include Relationable
    include Notifiable
    include Filterable

    belongs_to :author, -> { with_hidden }, class_name: 'User', foreign_key: 'author_id'
    belongs_to :heading
    belongs_to :group
    belongs_to :budget
    belongs_to :administrator

    has_many :valuator_assignments, dependent: :destroy
    has_many :valuators, through: :valuator_assignments

    has_many :comments, -> {where(valuation: false)}, as: :commentable, class_name: 'Comment'
    has_many :valuations, -> {where(valuation: true)}, as: :commentable, class_name: 'Comment'

    has_many :milestones

    has_many :lines, class_name: "Budget::Ballot::Line"

    validates :title, presence: true
    validates :author, presence: true
    validates :description, presence: true
    validates :heading_id, presence: true
    validates :unfeasibility_explanation, presence: { if: :unfeasibility_explanation_required? }
    validates :price, presence: { if: :price_required? }

    validates :title, length: { in: 4..Budget::Investment.title_max_length }
    # validates :description, length: { maximum: Budget::Investment.description_max_length }
    validate :description_length

    validates :terms_of_service, acceptance: { allow_nil: false }, on: :create

    scope :sort_by_confidence_score, -> { reorder(confidence_score: :desc, id: :desc) }
    scope :sort_by_ballots,          -> { reorder(ballot_lines_count: :desc, id: :desc) }
    scope :sort_by_price,            -> { reorder(price: :desc, confidence_score: :desc, id: :desc) }
    #scope :sort_by_random,           -> { reorder("RANDOM()") }
    scope :sort_by_random,           ->(seed) { reorder("budget_investments.id % #{seed.to_f.nonzero? ? seed.to_f : 1}, budget_investments.id") }
    scope :sort_by_created_at, -> {reorder(:created_at)}

    scope :valuation_open,              -> { where(valuation_finished: false) }
    scope :without_admin,               -> { valuation_open.where(administrator_id: nil) }
    scope :without_valuator,            -> { valuation_open.where(valuator_assignments_count: 0) }
    scope :under_valuation,             -> { valuation_open.where("valuator_assignments_count > 0 AND administrator_id IS NOT ?", nil) }
    scope :managed,                     -> { valuation_open.where(valuator_assignments_count: 0).where("administrator_id IS NOT ?", nil) }
    scope :valuating,                   -> { valuation_open.where("valuator_assignments_count > 0") }
    scope :valuation_finished,          -> { where(valuation_finished: true) }
    scope :valuation_finished_feasible, -> { where(valuation_finished: true, feasibility: "feasible") }
    scope :feasible,                    -> { where(feasibility: "feasible") }
    scope :unfeasible,                  -> { where(feasibility: "unfeasible") }
    scope :not_unfeasible,              -> { where.not(feasibility: "unfeasible") }
    scope :undecided,                   -> { where(feasibility: "undecided") }
    scope :with_supports,               -> { where('cached_votes_up > 0') }
    scope :selected,                    -> { feasible.where(selected: true) }
    #scope :selected_undecided,          -> { where(selected: true) }
    scope :compatible,                  -> { where(incompatible: false) }
    scope :incompatible,                -> { where(incompatible: true) }
    scope :winners,                     -> { selected.compatible.where(winner: true) }
    scope :unselected,                  -> { not_unfeasible.where(selected: false) }
    scope :unselected_undecided,        -> { where(selected: false) }
    scope :last_week,                   -> { where("created_at >= ?", 7.days.ago)}
    scope :selected_by_assembly,        -> { where(selected_by_assembly: true) }
    scope :unselected_by_assembly,        -> { where(selected_by_assembly: false) }

    scope :by_group,    ->(group_id)    { where(group_id: group_id) }
    scope :by_heading,  ->(heading_id)  { where(heading_id: heading_id) }
    scope :by_admin,    ->(admin_id)    { where(administrator_id: admin_id) }
    scope :by_tag,      ->(tag_name)    { tagged_with(tag_name) }
    scope :by_valuator, ->(valuator_id) { where("budget_valuator_assignments.valuator_id = ?", valuator_id).joins(:valuator_assignments) }

    scope :hidden, -> { unscoped.where.not(hidden_at: nil) }

    scope :flagged, -> { where("flags_count >= 0") }
    scope :pendientes_moderacion, -> { where(ignored_flag_at: nil).not_unfeasible }

    scope :for_render, -> { includes(:heading, author: :organization).preload(:tags) }

    # scope :for_render, -> { includes(:heading) }

    before_save :calculate_confidence_score
    after_save :recalculate_heading_winners if :incompatible_changed?
    before_validation :set_responsible_name
    before_validation :set_denormalized_ids

    def mark_unfeasible
      feasibility = 'unfeasible'
      valuation_finished = true
      save
    end

    def aviso_inviable
      Mailer.budget_investment_moderated_unfeasible(self).deliver
    end

    def aviso_moderacion
      Mailer.budget_investment_moderated_hide(self).deliver
    end

    def comments_count
      comments.count
    end

    def url
      budget_investment_path(budget, self)
    end

    def self.filter_params(params)
      params.select{ |x, _| %w{heading_id group_id administrator_id tag_name valuator_id}.include?(x.to_s) }
    end

    def self.scoped_filter(params, current_filter)
      budget  = Budget.find_by(id: params[:budget_id]) || Budget.find_by(slug: params[:budget_id])
      results = Investment.where(budget_id: budget.id)

      results = limit_results(budget, params, results)              if params[:max_per_heading].present?
      results = results.where(group_id: params[:group_id])          if params[:group_id].present?
      results = results.by_tag(params[:tag_name])                   if params[:tag_name].present?
      results = results.by_heading(params[:heading_id])             if params[:heading_id].present?
      results = results.by_valuator(params[:valuator_id])           if params[:valuator_id].present?
      results = results.by_admin(params[:administrator_id])         if params[:administrator_id].present?
      results = advanced_filters(params, results)                   if params[:advanced_filters].present?

      results = results.send(current_filter)                        if current_filter.present?
      results.includes(:heading, :group, :budget, administrator: :user, valuators: :user)
    end

    def self.advanced_filters(params, results)
      ids = []
      ids += results.valuation_finished_feasible.pluck(:id) if params[:advanced_filters].include?('feasible')
      ids += results.where(selected: true).pluck(:id)       if params[:advanced_filters].include?('selected')
      ids += results.undecided.pluck(:id)                   if params[:advanced_filters].include?('undecided')
      ids += results.unfeasible.pluck(:id)                  if params[:advanced_filters].include?('unfeasible')
      results.where("budget_investments.id IN (?)", ids)
    end

    def self.limit_results(budget, params, results)
      max_per_heading = params[:max_per_heading].to_i
      return results if max_per_heading <= 0

      ids = []
      budget.headings.pluck(:id).each do |hid|
        ids += Investment.where(heading_id: hid).order(confidence_score: :desc).limit(max_per_heading).pluck(:id)
      end

      results.where("budget_investments.id IN (?)", ids)
    end

    def self.search_by_title_or_id(params)
      results = Investment.where(budget_id: params[:budget_id])

      return results.where(id: params[:title_or_id]) if params[:title_or_id] =~ /\A[0-9]+\z/
      results.where("title ILIKE ?", "%#{params[:title_or_id].strip}%")
    end

    def searchable_values
      { title              => 'A',
        author.username    => 'B',
        heading.try(:name) => 'B',
        tag_list.join(' ') => 'B',
        description        => 'C'
      }
    end

    def self.search(terms)
      pg_search(terms)
    end

    def self.by_heading(heading)
      where(heading_id: heading == 'all' ? nil : heading.presence)
    end

    def undecided?
      feasibility == "undecided"
    end

    def feasible?
      feasibility == "feasible"
    end

    def unfeasible?
      feasibility == "unfeasible"
    end

    def unfeasibility_explanation_required?
      unfeasible? && valuation_finished?
    end

    def price_required?
      feasible? && valuation_finished?
    end

    def unfeasible_email_pending?
      unfeasible_email_sent_at.blank? && unfeasible? && valuation_finished?
    end

    def total_votes
      cached_votes_up + physical_votes
    end

    def code
      "#{created_at.strftime('%Y')}-#{id}" + (administrator.present? ? "-A#{administrator.id}" : "")
    end

    def send_unfeasible_email
      Mailer.budget_investment_unfeasible(self).deliver_later
      update(unfeasible_email_sent_at: Time.current)
    end

    def reason_for_not_being_selectable_by(user)
      return permission_problem(user) if permission_problem?(user)
      # return :different_heading_assigned unless valid_heading?(user)
      return :no_selecting_allowed unless budget.selecting?
    end

    def reason_for_not_being_ballotable_by(user, ballot)
      return permission_problem(user)    if permission_problem?(user)
      return :not_selected               unless selected?
      return :no_ballots_allowed         unless budget.balloting?
      return :different_heading_assigned unless ballot.valid_heading?(heading)
      return :not_enough_money_html      if ballot.present? && !enough_money?(ballot)
    end

    def permission_problem(user)
      return :not_logged_in unless user
      return :organization  if user.organization?
      return :not_verified  unless user.verified_at?
      return :quota_exceeded  if user.cannot?(:vote, Budget::Investment)
      nil
    end

    def permission_problem?(user)
      permission_problem(user).present?
    end

    def selectable_by?(user)
      reason_for_not_being_selectable_by(user).blank?
    end

    def valid_heading?(user)
      !different_heading_assigned?(user)
    end

    def different_heading_assigned?(user)
      other_heading_ids = group.heading_ids - [heading.id]
      voted_in?(other_heading_ids, user)
    end

    def voted_in?(heading_ids, user)
      heading_ids.include? heading_voted_by_user?(user)
    end

    def heading_voted_by_user?(user)
      user.votes.for_budget_investments(budget.investments.where(group: group))
          .votables.map(&:heading_id).first
    end

    def ballotable_by?(user)
      reason_for_not_being_ballotable_by(user).blank?
    end

    def enough_money?(ballot)
      available_money = ballot.amount_available(heading)
      price.to_i <= available_money
    end

    def register_selection(user)
      vote_by(voter: user, vote: 'yes') if selectable_by?(user) && user.can?(:vote, Budget::Investment)
    end

    def calculate_confidence_score
      self.confidence_score = ScoreCalculator.confidence_score(total_votes, total_votes)
    end

    def recalculate_heading_winners
      Budget::Result.new(budget, heading).calculate_winners if incompatible_changed?
    end

    def set_responsible_name
      self.responsible_name = author.try(:document_number) if author.try(:document_number).present?
    end

    def should_show_aside?
      (budget.selecting? && !unfeasible?) ||
        (budget.balloting? && feasible?) ||
        (budget.valuating? && !unfeasible?)
    end

    def should_show_votes?
      budget.selecting? && !selected_by_assembly
    end

    def should_show_vote_count?
      budget.valuating?
    end

    def should_show_ballots?
      budget.balloting? && selected?
    end

    def should_show_price?
      selected? && price.present? && budget.published_prices?
    end

    def should_show_price_explanation?
      should_show_price? && price_explanation.present?
    end

    def formatted_price
      budget.formatted_amount(price)
    end

    def self.apply_filters_and_search(budget, params, current_filter = nil)
      investments = all
      investments = investments.send(current_filter) if current_filter.present?
      if params[:unfeasible].present?
        investments = investments.unfeasible
      else
        investments = investments.not_unfeasible
      end
      investments = investments.unfeasible if params[:unfeasible].present?
      investments = investments.selected if budget.balloting?
      # else
      #   investments = params[:unfeasible].present? ? investments.unfeasible : investments.not_unfeasible
      # end
      # investments = investments.send(current_filter)            if current_filter.present?
      investments = investments.by_heading(params[:heading_id]) if params[:heading_id].present?
      investments = investments.search(params[:search])         if params[:search].present?
      investments = investments.filter(params[:advanced_search]) if params[:advanced_search].present?
      investments
    end

    def self.to_csv(investments, options = {})
      attrs = [I18n.t("admin.budget_investments.index.table_id"),
               I18n.t("admin.budget_investments.index.table_title"),
               I18n.t("admin.budget_investments.index.table_supports"),
               I18n.t("admin.budget_investments.index.table_admin"),
               I18n.t("admin.budget_investments.index.table_valuator"),
               I18n.t("admin.budget_investments.index.table_geozone"),
               I18n.t("admin.budget_investments.index.table_feasibility"),
               I18n.t("admin.budget_investments.index.table_valuation_finished"),
               I18n.t("admin.budget_investments.index.table_selection")]
      csv_string = CSV.generate(options) do |csv|
        csv << attrs
        investments.each do |investment|
          id = investment.id.to_s
          title = investment.title
          total_votes = investment.total_votes.to_s
          admin = if investment.administrator.present?
                    investment.administrator.name
                  else
                    I18n.t("admin.budget_investments.index.no_admin_assigned")
                  end
          vals = if investment.valuators.empty?
                   I18n.t("admin.budget_investments.index.no_valuators_assigned")
                 else
                   investment.valuators.collect(&:description_or_name).join(', ')
                 end
          heading_name = investment.heading.name
          price_string = "admin.budget_investments.index.feasibility"\
                         ".#{investment.feasibility}"
          price = I18n.t(price_string, price: investment.formatted_price)
          valuation_finished = investment.valuation_finished? ?
                                         I18n.t('shared.yes') :
                                         I18n.t('shared.no')
          csv << [id, title, total_votes, admin, vals, heading_name, price,
                  valuation_finished]
        end
      end
      csv_string
    end

    def update_cached_ballots_up
      self.cached_ballots_up = lines.size
      save
    end

    private

    def self.regenerate_cached_ballots_up
      includes(:lines).each do |i|
        i.update_cached_ballots_up
      end
    end

    def set_denormalized_ids
      self.group_id ||= self.heading.try(:group_id)
      self.budget_id ||= self.heading.try(:group).try(:budget_id)
    end

      # def set_denormalized_ids
      #   self.group_id = heading.try(:group_id) if heading_id_changed?
      #   self.budget_id ||= heading.try(:group).try(:budget_id)
      # end

    def description_length
      text = Html2Text.convert(description)
      max = Budget::Investment.description_max_length
      errors.add(:description, I18n.t('errors.messages.too_long', count: max)) if text.length > max
    end
  end
end

# == Schema Information
#
# Table name: budget_investments
#
#  id                         :integer          not null, primary key
#  author_id                  :integer
#  administrator_id           :integer
#  title                      :string
#  description                :text
#  external_url               :string
#  price                      :integer
#  feasibility                :string(15)       default("undecided")
#  price_explanation          :text
#  unfeasibility_explanation  :text
#  internal_comments          :text
#  valuation_finished         :boolean          default(FALSE)
#  valuator_assignments_count :integer          default(0)
#  price_first_year           :integer
#  duration                   :string
#  hidden_at                  :datetime
#  cached_votes_up            :integer          default(0)
#  comments_count             :integer          default(0)
#  confidence_score           :integer          default(0), not null
#  physical_votes             :integer          default(0)
#  tsv                        :tsvector
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  heading_id                 :integer
#  responsible_name           :string
#  budget_id                  :integer
#  group_id                   :integer
#  selected                   :boolean          default(FALSE)
#  location                   :string
#  organization_name          :string
#  unfeasible_email_sent_at   :datetime
#  ignored_flag_at            :datetime
#  moderation_text            :text
#  flags_count                :integer          default(0)
#  cached_ballots_up          :integer          default(0), not null
#  ballot_lines_count         :integer          default(0)
#  previous_heading_id        :integer
#  winner                     :boolean          default(FALSE)
#  incompatible               :boolean          default(FALSE)
#  community_id               :integer
#  selected_by_assembly       :boolean          default(FALSE), not null
#

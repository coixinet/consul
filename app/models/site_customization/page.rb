class SiteCustomization::Page < ActiveRecord::Base
  VALID_STATUSES = %w(draft published)

  validates :slug, presence: true,
                   uniqueness: { case_sensitive: false },
                   format: { with: /\A[0-9a-zA-Z\-_]*\Z/, message: :slug_format }
  validates :title, presence: true
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validates :locale, presence: true

  scope :published, -> { where(status: 'published').order('id DESC') }
  scope :with_more_info_flag, -> { where(status: 'published', more_info_flag: true).order('id ASC') }
  scope :with_same_locale, -> { where(locale: I18n.locale).order('id ASC') }

  def url
    "/#{slug}"
  end
end

# == Schema Information
#
# Table name: site_customization_pages
#
#  id                 :integer          not null, primary key
#  slug               :string           not null
#  title              :string           not null
#  subtitle           :string
#  content            :text
#  more_info_flag     :boolean
#  print_content_flag :boolean
#  status             :string           default("draft")
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  locale             :string
#

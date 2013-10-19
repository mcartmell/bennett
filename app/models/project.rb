class Project < ActiveRecord::Base
  has_many :builds, dependent: :destroy
  has_many :commands, dependent: :destroy
  accepts_nested_attributes_for :commands
  has_many :rights
  has_many :users, through: :rights

  validates :folder_path, uniqueness: true
  validate :unique_command_positions
  validates :name, :folder_path, :branch, :hook_token, presence: true

  before_validation :create_hook_token, on: :create

  scope :public, where(public: true)

  def self.build_all_nightly!
    Project.where(build_nightly: true).each do |project|
      project.build_all_new!(true)
    end
    return
  end

  def self.build_all_new!
    Project.all.each {|proj| proj.build_all_new!}
    return
  end

  def build_all_new!(include_default = false)
    all_new_branches(include_default).each do |build|
      if build.save
        Resque.enqueue(CommitsFetcher, build.id)
      else
        Rails.logger.error("Couldn't save build: #{build.errors}")
      end
    end
    return
  end

  def all_new_branches(include_default = false)
    g = Git.open(folder_path)
    all_branches = g.branches.remote.map(&:name)
    builds = all_branches.map {|br| self.builds.new(branch: br)}
    fetch = g.fetch

    # Always build the default branch if requested
    builds.select {|b| b.new_activity?(fetch) || (include_default && (b.branch == self.branch)) }
  end

  def last_build
    builds.last
  end

  def last_finished_build
    builds.last_finished
  end

  def status
    never_built? ? :no_builds : last_build.status
  end

  def finished_status
    last_finished_build.try :status
  end
  def has_finished_status?
    finished_status.present?
  end

  def never_built?
    builds.none?
  end

  def busy_or_pending?
    last_build.present? && (last_build.busy? || last_build.pending?)
  end

  def unique_command_positions
    errors.add(:commands, 'must have a non-ambiguous order') unless commands.map(&:position).size == commands.map(&:position).uniq.size
  end

private

  def create_hook_token
    self.hook_token = SecureRandom.hex(8)
  end

end

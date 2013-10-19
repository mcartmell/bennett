class BuildsController < ApplicationController
  load_and_authorize_resource except: :create

  # POST /builds
  # POST /builds.json
  def create
    @project = Project.find(params[:project_id])
    @manual = params[:manual]

    builds = []

    if branch = params[:branch]
      builds = [@project.builds.new(branch: branch)]
    else
      builds = @project.all_new_branches(@manual)
    end

    if params[:t].present?
      raise CanCan::AccessDenied unless @project.hook_token == params[:t]
    else
      authorize! :create, @build
    end

    # try to create builds

    @build_errors = []
    @builds_added = 0
    builds.each do |build|
      if build.save
        Resque.enqueue(CommitsFetcher, build.id)
        @builds_added += 1
      else
        @build_errors += build.errors
      end
    end

    respond_to do |format|
      if builds.empty?
        format.json { render status: :not_modified, json: {}; return }
        format.html { redirect_to @project, notice: 'No builds added' }
      else
        if @builds_added == builds.size
          format.json { render json: builds, status: :created; return }
          format.html { redirect_to @project, notice: "#{@builds_added} builds successfully added to queue." }
        elsif @builds_added == 0
          format.json { render json: @build_errors, status: :unprocessable_entity; return }
          format.html { redirect_to @project, notice: 'Error adding builds' }
        else
          format.json { render json: @build_errors, status: :created; return }
          format.html { redirect_to @project, notice: "#{@builds_added} out of #{builds.size} added. There were some errors." }
        end
      end
    end
  end

  def destroy
    @build = Build.find(params[:id])
    @build.delete_jobs_in_queues
    if @build.destroy
      flash[:notice] = "Build successfully deleted."
      redirect_to project_path(@build.project)
    else
      flash[:error] = "Error deleting build."
      redirect_to project_path(@build.project)
    end
  end
end

import csv
import json
from collections import defaultdict

# Read the CSV file and convert to hierarchical JSON structure
csv_file_path = ''
json_file_path = ''

# Dictionary to store pipelines
pipelines = defaultdict(lambda: {
    'pipeline_info': {},
    'workflows': defaultdict(lambda: {
        'workflow_info': {},
        'jobs': []
    })
})

# Read CSV and organize by pipeline -> workflow -> jobs
with open(csv_file_path, 'r', encoding='utf-8') as csv_file:
    csv_reader = csv.DictReader(csv_file)
    
    for row in csv_reader:
        pipeline_id = row['PIPELINE_ID']
        workflow_id = row['WORKFLOW_ID']
        
        # Store pipeline info (only once per pipeline)
        if not pipelines[pipeline_id]['pipeline_info']:
            pipelines[pipeline_id]['pipeline_info'] = {
                'pipeline_id': row['PIPELINE_ID'],
                'pipeline_number': row['PIPELINE_NUMBER'],
                'pipeline_created_at': row['PIPELINE_CREATED_AT'],
                'organization_id': row['ORGANIZATION_ID'],
                'organization_name': row['ORGANIZATION_NAME'],
                'project_id': row['PROJECT_ID'],
                'project_name': row['PROJECT_NAME'],
                'vcs_name': row['VCS_NAME'],
                'vcs_url': row['VCS_URL'],
                'vcs_branch': row['VCS_BRANCH'],
                'pipeline_trigger_source': row['PIPELINE_TRIGGER_SOURCE'],
                'pipeline_trigger_user_id': row['PIPELINE_TRIGGER_USER_ID'],
                'is_unregistered_user': row['IS_UNREGISTERED_USER']
            }
        
        # Store workflow info (only once per workflow)
        if not pipelines[pipeline_id]['workflows'][workflow_id]['workflow_info']:
            pipelines[pipeline_id]['workflows'][workflow_id]['workflow_info'] = {
                'workflow_id': row['WORKFLOW_ID'],
                'workflow_name': row['WORKFLOW_NAME'],
                'workflow_first_job_queued_at': row['WORKFLOW_FIRST_JOB_QUEUED_AT'],
                'workflow_first_job_started_at': row['WORKFLOW_FIRST_JOB_STARTED_AT'],
                'workflow_stopped_at': row['WORKFLOW_STOPPED_AT'],
                'is_workflow_successful': row['IS_WORKFLOW_SUCCESSFUL']
            }
        
        # Add job info
        job = {
            'job_id': row['JOB_ID'],
            'job_name': row['JOB_NAME'],
            'job_run_number': row['JOB_RUN_NUMBER'],
            'job_run_date': row['JOB_RUN_DATE'],
            'job_run_queued_at': row['JOB_RUN_QUEUED_AT'],
            'job_run_started_at': row['JOB_RUN_STARTED_AT'],
            'job_run_stopped_at': row['JOB_RUN_STOPPED_AT'],
            'job_build_status': row['JOB_BUILD_STATUS'],
            'resource_class': row['RESOURCE_CLASS'],
            'operating_system': row['OPERATING_SYSTEM'],
            'executor': row['EXECUTOR'],
            'parallelism': row['PARALLELISM'],
            'job_run_seconds': row['JOB_RUN_SECONDS'],
            'median_cpu_utilization_pct': row['MEDIAN_CPU_UTILIZATION_PCT'],
            'max_cpu_utilization_pct': row['MAX_CPU_UTILIZATION_PCT'],
            'median_ram_utilization_pct': row['MEDIAN_RAM_UTILIZATION_PCT'],
            'max_ram_utilization_pct': row['MAX_RAM_UTILIZATION_PCT'],
            'credits': {
                'compute_credits': row['COMPUTE_CREDITS'],
                'dlc_credits': row['DLC_CREDITS'],
                'user_credits': row['USER_CREDITS'],
                'storage_credits': row['STORAGE_CREDITS'],
                'network_credits': row['NETWORK_CREDITS'],
                'lease_credits': row['LEASE_CREDITS'],
                'lease_overage_credits': row['LEASE_OVERAGE_CREDITS'],
                'ipranges_credits': row['IPRANGES_CREDITS'],
                'total_credits': row['TOTAL_CREDITS']
            }
        }
        
        pipelines[pipeline_id]['workflows'][workflow_id]['jobs'].append(job)

# Convert defaultdict to regular dict and restructure for JSON output
output_data = []
for pipeline_id, pipeline_data in pipelines.items():
    pipeline_obj = pipeline_data['pipeline_info'].copy()
    pipeline_obj['workflows'] = []
    
    for workflow_id, workflow_data in pipeline_data['workflows'].items():
        workflow_obj = workflow_data['workflow_info'].copy()
        workflow_obj['jobs'] = workflow_data['jobs']
        pipeline_obj['workflows'].append(workflow_obj)
    
    output_data.append(pipeline_obj)

# Write to JSON file
with open(json_file_path, 'w', encoding='utf-8') as json_file:
    json.dump(output_data, json_file, indent=2)

print(f"Successfully converted CSV to hierarchical JSON")
print(f"Total pipelines: {len(output_data)}")
total_workflows = sum(len(p['workflows']) for p in output_data)
total_jobs = sum(len(w['jobs']) for p in output_data for w in p['workflows'])
print(f"Total workflows: {total_workflows}")
print(f"Total jobs: {total_jobs}")
print(f"JSON file saved to: {json_file_path}")

import boto3
import csv
import os
import tempfile

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Define bucket name and prefix
        bucket_name = 'dfragata-test-bucket'
        prefix = 'connectivity-output/'
        
        # Temporary directory to store CSV files
        temp_dir = tempfile.gettempdir()
        
        # Download all CSV files with the given prefix
        csv_files = []
        response = s3.list_objects_v2(Bucket=bucket_name, Prefix=prefix)
        if 'Contents' in response:
            for obj in response['Contents']:
                key = obj['Key']
                if key.endswith('.csv'):
                    file_name = os.path.join(temp_dir, os.path.basename(key))
                    s3.download_file(bucket_name, key, file_name)
                    csv_files.append(file_name)
        else:
            return {
                'statusCode': 404,
                'body': 'No CSV files found in the specified location.'
            }
        
        if not csv_files:
            return {
                'statusCode': 404,
                'body': 'No CSV files found in the specified location.'
            }
        
        # Compile CSV files into one
        compiled_csv = os.path.join(temp_dir, 'compiled.csv')
        with open(compiled_csv, 'w', newline='') as outfile:
            writer = csv.writer(outfile)
            for index, file in enumerate(csv_files):
                with open(file, 'r') as infile:
                    reader = csv.reader(infile)
                    # Skip header for all files except the first one
                    if index > 0:
                        next(reader, None)  # Skip the header row
                    writer.writerows(reader)
        
        # Upload compiled CSV file back to S3
        compiled_key = f"{prefix}compiled.csv"
        s3.upload_file(compiled_csv, bucket_name, compiled_key)
        
        return {
            'statusCode': 200,
            'body': 'Compilation and upload completed successfully!'
        }
    
    except Exception as e:
        return {
            'statusCode': 500,
            'body': f'An error occurred: {str(e)}'
        }

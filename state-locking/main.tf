#create S3 bucket and dynamodb table but make sure you make key which name "LockID" it is fix
#you can not change it 



terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket" # change 
    key            = "project1/terraform.tfstate"# change 
    region         = "us-east-1"# change 
    dynamodb_table = "terraform-locks"# change 
  }
}
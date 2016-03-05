# Docker and ECS

Date | Comments | Author
----- | ------  | ------
Last updated|March 5, 2015| Sriram Rajan


## Overview

In this article we will look at the AWS ECS as service and how it could be used to deploy Docker containers. We will also provide examples for a step by step deployment on ECS.

### Docker
Docker and containers are increasingly becoming popular and offer serveral benefits from a development and delivery perspective. Similar to the way CloudFormation can provision AWS services, Docker provides a declarative syntax for creating containers. 

At a high level Docker architecture looks like this.

![image](images/docker-architecture.svg =500x300)
*Source: https://docs.docker.com/engine/understanding-docker/*

For more about Docker architecure, refer to [Understand the architecture](https://docs.docker.com/engine/understanding-docker/)


### ECS

ECS is a cluster management framework that provides

 - Management of EC2 instances that run as Docker Hosts. You can tie this to Autoscale groups and ELB like you would with other EC2 instances.
 
 - Scheduler to execute processes/containers on EC2 instances.
 
 - Constructs to deploy and manage versions of the applications.
 
 
Here are some core ECS concepts.

 - Cluster :  A logical grouping of EC2 container instances that run tasks. The cluster is more a skeleton around which build your workload.
 
 - Container Instance : This is actually an n EC2 instance running the ECS agent. The recomended way is to use AWS ECS AMI but any AMI can be used as long as you add the ECS agent to it.
 
 - Task Definition : An application containing one or more containers. This is where you provide the Docker images, how much CPU/Memory to use, ports etc. You can also link containers here similar to Docker command line.

 - Task : An instance of a task definition running on a container instance.
 
 - Service : A service in ECS allows you to run and maintain a specified number of instances of a task definition. If a task in a service stops, the task is restarted. Services ensure that desired running tasks is achieved and maintained. The service is also the place where you would include an ELB configuration.

 - Container : A Docker container that is part of a task.


## ECS Use cases

 - An easy way to deploy Docker with limited management overhead.
 
 - Part of the AWS ecosystem and so is easy to tie with other applications already running in AWS.

<NEED MORE>

 
## ECS Considerations


### Limitations

 - It is not available in all regions. This applies to both ECS and ECR (Elastic Container Registry)
 
 - You are limited to one port per task definition. This is by far the biggest drawback today. When creating a task, you can omit the "Host port" option and a port will automatically be chosen when it's started. However, when registering tasks behind ELBs, ELB currently requires that all EC2 instances have the same port registered (which is the ECS host port). This may get fixed in future releases and is actively discussed in [forums](https://forums.aws.amazon.com/message.jspa?messageID=665031)
 
 - Once the task is created, you cannot change port in a task definition. You will need to create a new one.
 

### Design Considerations


 - The biggest consideration is work around the port number limitation. If you need to lots of containers mapped to the same port numbers, you will need more EC2 instances. So going smaller instance size might help.
 
 - Service discovery is limited inside ECS. You can use environment variables in task definitions but that not service discovery per say. You can run something like Consul and use it for service discovery. AWS has a good blog article on this ; [https://aws.amazon.com/blogs/compute/service-discovery-via-consul-with-amazon-ecs/]( - https://aws.amazon.com/blogs/compute/service-discovery-via-consul-with-amazon-ecs/)
 
 - ECS allows external schedulers and the driver is open source. So you can use something like Mesos with ECS; [https://github.com/awslabs/ecs-mesos-scheduler-driver](https://github.com/awslabs/ecs-mesos-scheduler-driver) 
 
 - Autoscale is a perfect use-case for this type of workloads and so build the EC2 instances using an Autoscale policy.
 
## ECS Step by Step

### Goals 

Note, this assumes some familiarity with Git & Docker and AWS services like VPC, ELB, EC2. The goal of this tutorial is to achieve the following

 - Deploy two services into ECS, behind separate Elastic Load balancers
 
 - Deploy them using ECS cli and using the tasks and services
 
 - Perform a changes to the application anb deploy new versions
 
 - Review how ELB works with these changes
  
Architecturally, it looks like this:

![image](images/ecs-sample-app.png =400x400)


### Get ECS running

Now let's create the services we need to get started.

 - In this example we are building this in us-east-1 region.
 
 - Follow the AWS guide to get the necessary IAM roles etc in place for ECS [Setting Up with Amazon ECS](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/get-set-up-for-amazon-ecs.html)
 
  - Create a ECS cluster by going to the [Amazon ECS console](https://console.aws.amazon.com/ecs/) and selecting "Create Cluster".
 
 - In the cluster name field, enter a name for your cluster and create it. We used '*app01*' in this example but if you don't choose anything it uses 'default'
 
 - This creates a framework for ECS. Now we add EC2 instances to it. The best way to do this is via an Autoscaling group. So create an autoscale group with the lauch config and the amzn-ami-2015.09.g-amazon-ecs-optimized AMI
 
 - For this example, t2.medium was used but you can do micro instances if you want to avoid costs.
 
 - In the IAM section provide the corresonding ECS role created when preparing the account.
 
 - If you have changed the cluster name, then you need to add User data to the launch configuration.
 
```
 #!/bin/bash
echo ECS_CLUSTER=app01 >> /etc/ecs/ecs.config
```

 - Once the launch configuration is complete, in the Autoscale section, select 
 4 instances and give it a group name.
 
 - Then provide the ECS VPC and subnets for Autoscale.
 
 - Since this is a demo, we can keep group at initial size. But if you want you can play with the metrics and tie to this your cluster usage for acutal autoscaling.
 
 - Review and launch this. Then wait for a few minutes as the EC2 instances are spun up and start appearing under the ECS Instances section of your ECS cluster.
 
 
### Get ELB running

 - For this example create two ELB instances; location and user Creation of the ELB is the same as any ELB creation with the following differences
 
   - You have decide on the ports you will use for the services. In our example, we choose port 8081 for the location service and 9091 for the user service
   
   - Configure proper health checks as you would with any instance
   
   - Do not add any EC2 instances to it. This will be done later on in the ECS service side
   

### Get RDS running

 - You can skip this step but to make this more real world, we created a RDS instance that the containers will use for databases
 
 - Create an RDS DB of your choice and configure per normal
 
 - Note down the credentials and endpoints for later use

### Check the setup

At this point your setup should look like this.

```
aws ecs list-clusters
{
    "clusterArns": [
        "arn:aws:ecs:us-east-1:964129947503:cluster/app01"
    ]
}

aws ecs describe-clusters --cluster app01
{
    "clusters": [
        {
            "status": "ACTIVE", 
            "clusterName": "app01", 
            "registeredContainerInstancesCount": 4, 
            "pendingTasksCount": 0, 
            "runningTasksCount": 0, 
            "activeServicesCount": 0, 
            "clusterArn": "arn:aws:ecs:us-east-1:964028947503:cluster/app01"
        }
    ], 
    "failures": []
}

aws ecs list-container-instances --cluster app01
{
    "containerInstanceArns": [
        "arn:aws:ecs:us-east-1:962029947503:container-instance/0e9c2658-d9ca-432d-a1e7-5f74682c96f0", 
        "arn:aws:ecs:us-east-1:964029647503:container-instance/45e45208-b1ce-4ca4-96e9-62492f1540c4", 
        "arn:aws:ecs:us-east-1:964429947503:container-instance/c220903d-3165-434d-afe0-36b43d909ec1", 
        "arn:aws:ecs:us-east-1:963029947503:container-instance/ea49b768-c04e-439c-9264-2ca670589177"
    ]
}
```

Also make sure ELB and RDS instances are up and running.


### Docker Images

 - This can be any Docker images but the actual use case, we built a Docker image which runs Ubuntu, Nginx, PHP-fpm. We added some custom code to connect to RDS etc. All the source is available [https://github.com/srirajan/ecs-playground](https://github.com/srirajan/ecs-playground)
 
 - Build the docker images and upload them to your Docker hub. This example uses public images but you can also embedd credentials and use private images.
 
```
git clone https://github.com/srirajan/ecs-playground
cd ecs-playground
cd docker 
cd location
docker build -t="srirajan/location" .
docker push "srirajan/location"
cd ..
cd user
docker build -t="srirajan/user" .
docker push "srirajan/user"
```
 

### Deploying tasks and services

 - Once we have the images, lets start deploying. The first step is to create a task definion.

```
{
  "containerDefinitions": [
    {
      "name": "location",
      "image": "srirajan/location:10",
      "cpu": 512,
      "memory": 1024,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 8081,
          "hostPort": 8081
        }
      ],
      "environment": [
        { "name": "DB_HOST", "value": "ecsdb.cat6z9up2jds.us-east-1.rds.amazonaws.com" },
        { "name": "DB_USER", "value": "location" },
        { "name": "DB_PWD", "value": "RDS_PWD" },
        { "name": "DB_NAME", "value": "location" }
      ],
      "extraHosts": [
      {
        "hostname": "googledns",
        "ipAddress": "8.8.8.8"
      }
    ]
    }
  ],
  "family": "location"
}
```

The task represents a single container and includes several parameters:

family - is the name of the task definition.

name - is the container name.

image - is the public image on DockerHub.

cpu - is the number of cpu units to allocate (there are 1024 units per core).

memory - is the amount of memory to allocate in MB.

portMappings - This is key as we have configured our ELB to use this.

You can read about the parameters in detail here [http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html](http://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)

 - Set the region as it helps with the cli
 
```
export AWS_DEFAULT_REGION=us-east-1
```

 - Register the task defintion. This does not instantiate the task, so, nothing is running right now.

```
aws ecs register-task-definition --cli-input-json file://location.json
```

 - Update the Security groups associated with the ECS EC2 instances to allow the ports above. The ELB needs access to those ports.
 
 -  Now create the service definition using the following definition file
 
```
{
    "cluster": "app01",
    "serviceName": "location",
    "taskDefinition": "location",
    "loadBalancers": [
        {
            "loadBalancerName": "location",
            "containerName": "location",
            "containerPort": 8081
        }
    ],
    "desiredCount": 4,
    "clientToken": "lololololo",
    "role": "arn:aws:iam::964029947503:role/ecsServiceRole",
    "deploymentConfiguration": {
        "maximumPercent": 200,
        "minimumHealthyPercent": 50
    }
}
```

```
aws ecs create-service --cli-input-json file://location.json
```

- You can check the status via command line

```
aws ecs describe-services --services location --cluster app01
```

 - If all is working you will see a "runningCount" of 4 and the corresonding load balancer is now serving traffic.


 - Repeat the same for the User 

 -  User task

```
{
  "containerDefinitions": [
    {
      "name": "user",
      "image": "srirajan/user:1",
      "cpu": 512,
      "memory": 1024,
      "essential": true,
      "portMappings": [
        {
          "containerPort": 9091,
          "hostPort": 9091
        }
      ],
      "environment": [
        { "name": "DB_HOST", "value": "ecsdb.cat6z9up2jds.us-east-1.rds.amazonaws.com" },
        { "name": "DB_USER", "value": "user" },
        { "name": "DB_PWD", "value": "1QAZ2wsx3edc" },
        { "name": "DB_NAME", "value": "user" }
      ],
      "extraHosts": [
      {
        "hostname": "googledns",
        "ipAddress": "8.8.8.8"
      }
    ]
    }
  ],
  "family": "user"
}
```

```
aws ecs register-task-definition --cli-input-json file://user.json
```


 - User Service
 
```
{
    "cluster": "app01",
    "serviceName": "user",
    "taskDefinition": "user",
    "loadBalancers": [
        {
            "loadBalancerName": "user",
            "containerName": "user",
            "containerPort": 9091
        }
    ],
    "desiredCount": 4,
    "clientToken": "usususus",
    "role": "arn:aws:iam::964029947503:role/ecsServiceRole",
    "deploymentConfiguration": {
        "maximumPercent": 200,
        "minimumHealthyPercent": 50
    }
}
```

```
aws ecs create-service --cli-input-json file://user.json
```

```
aws ecs describe-services --services user --cluster app01
```


 - At this point we have two services each running 4 docker containers on top of 4 EC2 instances. You can look at the ELB setup and you will now see instances in service.  The ECS console will also show them as active. 

 - Now if we decide to change the application, you will make the changes to the docker image and push it back to Docker hub, under a new tag (version)
 
 
 - Then you update the json file for the task definition with the new tag. The only thing that changes in the json file is the image link. If you don't use tags and rely on the latest docker image, then no change is needed to the json file.

 - Update the task definition to a new verion. In this example, location task definition has changed to version 11
 
```
aws ecs register-task-definition --cli-input-json file://user.json
```

 - Then we update the service to use the new version. In an update scenario, minimumHealthyPercent plays an important part. This ensures, the upgrade is rolled out in a rolling fashion and the service never goes below the minimumHealthyPercent.
 
```
aws ecs update-service --cluster default --service location --desired-count 4 --task-definition location:11 --deployment-configuration maximumPercent=200,minimumHealthyPercent=50
```

 - That's ends this tutorial. Play around with the AWS console, especially, the metrics tab to view the usage of your cluster.

### What next

Here are some other areas that could be explored to add more functionality to an ECS solution.

 - Extend this example to use Consul for service description
 
 - Extend Consul to manage the ELB for us. This could be used to overcome the limitation of port numbers in ECS
 
 - Introduce other one-time tasks and see how they can be scheduled in ECS
 
 - Test other scheduler drivers
 
 - Build autoscale based on container and ECS metrics


## Conclusion
<TBC>


==========


## References and Links

 - https://rossfairbanks.com/2015/03/31/hello-world-in-ec2-container-service.html
 
 - https://medium.com/aws-activate-startup-blog/cluster-based-architectures-using-docker-and-amazon-ec2-container-service-f74fa86254bf#.8hzyk61hb 
 
 - http://docs.aws.amazon.com/cli/latest/reference/ecs/
  
==========

## Credits


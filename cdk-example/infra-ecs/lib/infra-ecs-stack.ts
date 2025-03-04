import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { checkBuildEnvironmentVariables } from '../../utils/environment';

// AWS ECR imports
import { DockerImageAsset } from 'aws-cdk-lib/aws-ecr-assets';

// AWS ECS imports
import { Cluster, ContainerImage } from 'aws-cdk-lib/aws-ecs';

// AWS ECS Patterns imports
import { ApplicationLoadBalancedFargateService } from 'aws-cdk-lib/aws-ecs-patterns';

// AWS ELBv2 import
import { ApplicationProtocol } from 'aws-cdk-lib/aws-elasticloadbalancingv2';

// AWS Route53 imports
import { LoadBalancerTarget } from 'aws-cdk-lib/aws-route53-targets';
import { HostedZone, ARecord, RecordTarget } from 'aws-cdk-lib/aws-route53';

// AWS Certificate Manager import
import {
  Certificate,
  CertificateValidation,
} from 'aws-cdk-lib/aws-certificatemanager';

interface Env {
  hostedZoneId?: string;
  domainNameSSL?: string;
  zoneName?: string;
  recordName?: string;
}

interface EnvMap {
  [index: string]: Env;
}

const envName: string | undefined =
  process.env.ENV_NAME && process.env.ENV_NAME.toLowerCase();

export class InfraEcsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    if (!envName || !checkBuildEnvironmentVariables({ envName: envName })) {
      throw new Error('Invalid environment variables.');
    }

    const envMap: EnvMap = {
      devmaj: {
        hostedZoneId: 'Z3DCLNVJZZ5852',
        domainNameSSL: '*.sunrundev.com',
        zoneName: 'sunrundev.com',
        recordName: 'devmaj-preview.sunrundev.com',
      },
      majstg: {},
      prd: {
        hostedZoneId: 'ZW6XUTNBV9FDM',
        domainNameSSL: '*.sunrun.com',
        zoneName: 'sunrun.com',
        recordName: 'cms2-preview.sunrun.com',
      },
    };

    // Create a Docker image from a Dockerfile.
    const dockerImage = new DockerImageAsset(this, 'DockerImage', {
      buildArgs: {
        TOKEN_ENV: process.env.GITHUB_NPM_TOKEN || '',
        CONTENTFUL_PREVIEW_TOKEN: process.env.CONTENTFUL_PREVIEW_TOKEN || '',
        CONTENTFUL_PUBLISH_TOKEN: process.env.CONTENTFUL_PUBLISH_TOKEN || '',
        SITE: process.env.SITE || '',
        ENV_NAME: process.env.ENV_NAME || '',
        NEXT_PREVIEW_SECRET: process.env.NEXT_PREVIEW_SECRET || '',
      },
      directory: '../',
    });

    // Crea un clúster ECS
    const cluster = new Cluster(this, 'ECSCluster', {
      clusterName: `${envName}-multisite-preview-cluster`,
    });

    const publicZone = HostedZone.fromHostedZoneAttributes(
      this,
      'HttpsFargateAlbPublicZone',
      {
        zoneName: envMap[envName].zoneName || '',
        hostedZoneId: envMap[envName].hostedZoneId || '',
      }
    );

    const certificate = new Certificate(this, 'HttpsFargateAlbCertificate', {
      domainName: envMap[envName].domainNameSSL || '',
      validation: CertificateValidation.fromDns(publicZone),
    });

    // Create a Fargate service with a load balancer in the cluster.
    const service = new ApplicationLoadBalancedFargateService(
      this,
      'FargateService',
      {
        cluster,
        taskImageOptions: {
          image: ContainerImage.fromDockerImageAsset(dockerImage),
          containerPort: 3000,
        },
        desiredCount: 1,
        memoryLimitMiB: 2048,
        cpu: 512,
        protocol: ApplicationProtocol.HTTPS,
        certificate,
        redirectHTTP: true,
        healthCheckGracePeriod: cdk.Duration.minutes(5),
      }
    );
    service.targetGroup.configureHealthCheck({
      path: '/shop',
      timeout: cdk.Duration.seconds(20),
    });
    new ARecord(this, 'HttpsFargateAlbARecord', {
      zone: publicZone,
      recordName: envMap[envName].recordName || '',
      target: RecordTarget.fromAlias(
        new LoadBalancerTarget(service.loadBalancer)
      ),
    });
  }
}

const app = new cdk.App();
new InfraEcsStack(app, `${envName}-multisite-preview`);

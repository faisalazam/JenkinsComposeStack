# Jenkins Configuration as Code (JCasC)

This folder contains the modular Configuration as Code (JCasC) setup for Jenkins, enabling fully automated and
reproducible Jenkins instances using version-controlled YAML files.

---

## 📁 Folder Structure

```bash
casc_configs/
├— 01-jenkins.yml                # Core Jenkins settings
├— 02-security.yml               # Security realm and authorization settings
├— 03a-credentials-base.yml      # Jenkins credentials (e.g., Docker TLS certs)
├— 04-global-config.yml          # Global environment variables and node properties
├— 05-clouds-docker-agents.yml   # Docker cloud and agent templates
├— 06-unclassified.yml           # Plugin-specific and miscellaneous settings
└— dsl/
    └— jobs/
        └— jenkins-sanity-check-pipeline.yml  # Job DSL in YAML format
        └— seed-ansible-playbook-jobs.yml     # Seed Job DSL to generate pipeline for Ansible Playbooks
```

---

## 🧹 File Descriptions

| File                            | Description                                                           |
|---------------------------------|-----------------------------------------------------------------------|
| **01-jenkins.yml**              | Base Jenkins config: system message and executor count.               |
| **02-security.yml**             | Local user accounts and access control settings.                      |
| **03-credentials.yml**          | TLS certificates and other system credentials.                        |
| **04-global-config.yml**        | Global node properties such as environment variables.                 |
| **05-clouds-docker-agents.yml** | Docker cloud integration and agent templates.                         |
| **06-unclassified.yml**         | Additional plugin-specific configuration (mailer, timestamper, etc.). |
| **dsl/jobs/**                   | Folder containing YAML-defined pipeline jobs.                         |

---

## 📌 Usage

Ensure this directory is mounted to Jenkins using Docker Compose or another deployment mechanism.

Example Docker Compose volume:

```yaml
    volumes:
      - ./casc_configs:/var/jenkins_home/casc_configs
```

Also set the environment variable to enable JCasC:

```yaml
    environment:
      - CASC_JENKINS_CONFIG=/var/jenkins_home/casc_configs
```

---

## 📚 References

- [Jenkins Configuration as Code Plugin](https://github.com/jenkinsci/configuration-as-code-plugin)
- View live config reference: `http://<your-jenkins-host>/manage/configuration-as-code/reference`
- Export current config: `http://<your-jenkins-host>/manage/configuration-as-code/viewExport`

---

## ✅ Notes

- Order-prefixed YAML files ensure predictable config loading.
- Secrets (like passwords or certs) should be handled via environment variables or secret managers.


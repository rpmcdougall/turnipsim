# Developer Wiki

Comprehensive process and procedure documentation for Turnip28 Simulator development.

## 📚 Documentation Index

### Getting Started
- **[Home](Home.md)** - Wiki overview and navigation
- **[Project Setup](Project-Setup.md)** - Environment setup, dependencies, installation
- **[Architecture Overview](Architecture-Overview.md)** - System design and architectural decisions

### Development Workflow
- **[Development Process](Development-Process.md)** - Feature branches, commits, PRs, reviews
- **[Code Style Guide](Code-Style-Guide.md)** - GDScript conventions and patterns
- **[Testing Guidelines](Testing-Guidelines.md)** - Writing and running tests
- **[Commit Conventions](Commit-Conventions.md)** - Message format and types
- **[Session Discipline](Session-Discipline.md)** - Documentation and memory management

## Quick Links

### External Resources
- [GitHub Repository](https://github.com/rpmcdougall/turnipsim)
- [Project Board](https://github.com/users/rpmcdougall/projects/1)
- [Issues](https://github.com/rpmcdougall/turnipsim/issues)

### Project Documentation
- [CLAUDE.md](../../CLAUDE.md) - Project conventions and architecture
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Contribution guidelines
- [MEMORY.md](../../MEMORY.md) - Current project status

### Roadmap
- [turnip28-sim-plan-godot.md](../../turnip28-sim-plan-godot.md) - Full phase plan

## Using This Wiki

### For New Contributors

1. **Start here:** [Project Setup](Project-Setup.md)
2. **Understand the system:** [Architecture Overview](Architecture-Overview.md)
3. **Learn the workflow:** [Development Process](Development-Process.md)
4. **Write code:** [Code Style Guide](Code-Style-Guide.md)
5. **Add tests:** [Testing Guidelines](Testing-Guidelines.md)
6. **Test manually:** [Manual Testing Guide](Manual-Testing-Guide.md)

### For Existing Contributors

- **Starting a session?** Review [Session Discipline](Session-Discipline.md)
- **Making commits?** Check [Commit Conventions](Commit-Conventions.md)
- **Writing tests?** See [Testing Guidelines](Testing-Guidelines.md)
- **Testing manually?** Follow [Manual Testing Guide](Manual-Testing-Guide.md)
- **Implementing Phase 4 UI?** See [Phase 4 UI Tasks](Phase-4-UI-Tasks.md)
- **Architecture questions?** Consult [Architecture Overview](Architecture-Overview.md)

## GitHub Wiki

This documentation is designed to be:
1. **Used directly from the repo** (`docs/wiki/`)
2. **Migrated to GitHub Wiki** (if desired)
3. **Version controlled** alongside code

To publish to GitHub Wiki:
```bash
# Clone the wiki repo
git clone https://github.com/rpmcdougall/turnipsim.wiki.git

# Copy docs
cp docs/wiki/*.md turnipsim.wiki/

# Commit and push
cd turnipsim.wiki/
git add .
git commit -m "Update wiki documentation"
git push
```

## Contributing to the Wiki

Improvements to documentation are welcome! Follow the same process as code:

1. Create feature branch: `docs/wiki-improvement`
2. Update wiki pages in `docs/wiki/`
3. Create PR with changes
4. Review and merge

## Maintenance

**Update frequency:**
- **Session Discipline** docs: Update as workflow evolves
- **Code Style Guide**: Update when adopting new patterns
- **Testing Guidelines**: Update when adding test infrastructure
- **Architecture Overview**: Update after major architectural changes

**Keep in sync with:**
- CLAUDE.md (project conventions)
- MEMORY.md (current status)
- CONTRIBUTING.md (contribution workflow)

## License

This documentation is part of the Turnip28 Simulator project and follows the same license as the main project.

# Use official Node.js runtime as a parent image
FROM node:14

# Set the working directory to /app
WORKDIR /app

# Copy package.json and package-lock.json to the working directory
COPY package*.json ./

# Install application dependencies
RUN npm install

# Bundle the app source
COPY . .

# Expose port 3000 (adjust the port based on our application's port)
EXPOSE 3000

# Command to run your application
CMD ["npm", "start"]
